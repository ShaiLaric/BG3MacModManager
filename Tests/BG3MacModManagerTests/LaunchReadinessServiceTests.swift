// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import BG3MacModManager

final class LaunchReadinessServiceTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        temporaryURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        temporaryURLs.removeAll()
        super.tearDown()
    }

    func testMissingActivePAKIsCritical() async {
        let missing = URL(fileURLWithPath: "/tmp/bg3mm-missing-\(UUID().uuidString).pak")
        let mod = makeModInfo(uuid: "missing", name: "Missing Mod", pakFilePath: missing)

        let report = await LaunchReadinessService().evaluate(snapshot(activeMods: [mod]))

        XCTAssertEqual(report.overallState, .critical)
        XCTAssertTrue(report.criticalFindings.contains { $0.title == "Missing PAK: Missing Mod" })
        XCTAssertEqual(report.criticalFindings.first?.action, .openModsFolder)
    }

    func testValidPAKPassesFileInspection() async throws {
        let pakURL = try writeValidPAK()
        let mod = makeModInfo(uuid: "valid", name: "Valid Mod", pakFilePath: pakURL)

        let report = await LaunchReadinessService().evaluate(snapshot(activeMods: [mod]))

        XCTAssertFalse(report.findings.contains { $0.category == .files })
        XCTAssertEqual(report.overallState, .ready)
    }

    func testUnsavedOrderProducesActionableWarning() async {
        let report = await LaunchReadinessService().evaluate(snapshot(hasUnsavedChanges: true))

        let finding = report.findings.first { $0.title == "Load order has unsaved changes" }
        XCTAssertEqual(finding?.severity, .warning)
        XCTAssertEqual(finding?.action, .saveLoadOrder)
        XCTAssertEqual(report.overallState, .review)
    }

    func testValidationWarningIsMappedToReadinessFinding() async {
        let warning = ModWarning(
            severity: .critical,
            category: .missingDependency,
            message: "Missing dependency",
            detail: "Framework is not installed.",
            affectedModUUIDs: ["dependent"],
            suggestedAction: .activateDependencies(modUUID: "dependent")
        )

        let report = await LaunchReadinessService().evaluate(snapshot(validationWarnings: [warning]))

        let finding = report.findings.first { $0.title == "Missing dependency" }
        XCTAssertEqual(finding?.category, .order)
        XCTAssertEqual(finding?.action, .activateDependencies("dependent"))
    }

    func testUnavailableNexusCheckDoesNotReduceSafetyState() async {
        let report = await LaunchReadinessService().evaluate(snapshot(nexusConfigured: false))

        XCTAssertEqual(report.overallState, .ready)
        XCTAssertEqual(report.checks.first { $0.id == "nexus" }?.state, .unavailable)
    }

    func testStaleNexusResultIsAdvisory() async {
        let clock = Date(timeIntervalSince1970: 10_000)
        let result = NexusUpdateResult(
            modUUID: "mod",
            nexusModID: 42,
            installedVersion: "1.0.0",
            latestVersion: "2.0.0",
            latestName: "Mod",
            updatedDate: nil,
            nexusURL: "https://www.nexusmods.com/baldursgate3/mods/42",
            checkedDate: clock.addingTimeInterval(-(NexusAPIService.cacheMaxAge + 1))
        )
        let service = LaunchReadinessService(now: { clock })

        let report = await service.evaluate(snapshot(nexusConfigured: true, nexusResults: [result]))

        XCTAssertEqual(report.checks.first { $0.id == "nexus" }?.state, .stale)
        XCTAssertEqual(report.findings.first { $0.category == .updates }?.severity, .information)
        XCTAssertEqual(report.overallState, .ready)
    }

    func testSuppressedNexusResultDoesNotProduceFinding() async {
        let result = NexusUpdateResult(
            modUUID: "optional-file",
            nexusModID: 42,
            installedVersion: "1.0.0",
            latestVersion: "2.0.0",
            latestName: "Base Mod Page",
            updatedDate: nil,
            nexusURL: "https://www.nexusmods.com/baldursgate3/mods/42",
            checkedDate: Date()
        )

        let report = await LaunchReadinessService().evaluate(snapshot(
            nexusConfigured: true,
            nexusResults: [result],
            suppressedNexusResultIDs: ["optional-file"]
        ))

        XCTAssertFalse(report.findings.contains { $0.category == .updates })
        XCTAssertEqual(report.overallState, .ready)
    }

    func testEquivalentSnapshotsHaveStableIdentity() async throws {
        let pakURL = try writeValidPAK()
        let mod = makeModInfo(uuid: "stable", name: "Stable Mod", pakFilePath: pakURL)
        let first = await LaunchReadinessService(now: { Date(timeIntervalSince1970: 1_000) })
            .evaluate(snapshot(activeMods: [mod]))
        let second = await LaunchReadinessService(now: { Date(timeIntervalSince1970: 1_001) })
            .evaluate(snapshot(activeMods: [mod]))

        XCTAssertEqual(first.snapshotID, second.snapshotID)
        XCTAssertEqual(first.findings, second.findings)
        XCTAssertNotEqual(first.generatedAt, second.generatedAt)
    }

    private func snapshot(
        activeMods: [ModInfo] = [],
        validationWarnings: [ModWarning] = [],
        hasUnsavedChanges: Bool = false,
        nexusConfigured: Bool = false,
        nexusResults: [NexusUpdateResult] = [],
        suppressedNexusResultIDs: Set<String> = []
    ) -> LaunchReadinessSnapshot {
        LaunchReadinessSnapshot(
            activeMods: activeMods,
            inactiveMods: [],
            validationWarnings: validationWarnings,
            hasUnsavedChanges: hasUnsavedChanges,
            externalModSettingsChangeDetected: false,
            modSettingsExists: true,
            gameInstalled: true,
            steamRunning: true,
            gameRunning: false,
            nexusConfigured: nexusConfigured,
            nexusCheckInProgress: false,
            nexusResults: nexusResults,
            suppressedNexusResultIDs: suppressedNexusResultIDs
        )
    }

    private func writeValidPAK() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bg3mm-readiness-\(UUID().uuidString).pak")
        let data = makeUncompressedTestPak(entries: [
            (name: "Public/Test/readme.txt", contents: Data("ok".utf8)),
        ])
        try data.write(to: url)
        temporaryURLs.append(url)
        return url
    }
}
