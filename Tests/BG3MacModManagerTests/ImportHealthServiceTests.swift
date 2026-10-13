// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class ImportHealthServiceTests: XCTestCase {
    func testMissingDependencyHasInstallationAdvice() throws {
        let imported = makeModInfo(uuid: "new", dependencies: [makeDependency(uuid: "missing", name: "Required Library")])
        let finding = try XCTUnwrap(report([imported]).findings.first { $0.category == .missingDependency })
        XCTAssertEqual(finding.suggestedAction, .installDependency(name: "Required Library"))
        XCTAssertTrue(finding.detail.contains("not installed"))
    }

    func testActivePlaceholderDoesNotSatisfyMissingInstalledDependency() {
        let missing = makeModInfo(uuid: "missing", pakFileName: nil, metadataSource: .modSettings)
        let imported = makeModInfo(uuid: "new", dependencies: [makeDependency(uuid: "missing")])
        XCTAssertTrue(report([imported], active: [missing]).findings.contains { $0.category == .missingDependency })
    }

    func testInactiveInstalledDependencyCanBeActivated() throws {
        let library = makeModInfo(uuid: "library")
        let imported = makeModInfo(uuid: "new", dependencies: [makeDependency(uuid: "library")])
        let finding = try XCTUnwrap(report([imported], inactive: [library]).findings.first { $0.category == .missingDependency })
        XCTAssertEqual(finding.suggestedAction, .activateDependencies(modUUID: "new"))
        XCTAssertTrue(finding.detail.contains("inactive"))
    }

    func testDependenciesImportedTogetherAreAvailableInPreview() {
        let library = makeModInfo(uuid: "library")
        let imported = makeModInfo(uuid: "new", dependencies: [makeDependency(uuid: "library")])
        XCTAssertFalse(report([library, imported]).findings.contains { $0.category == .missingDependency })
    }

    func testDependencyIdentityIsCaseInsensitive() {
        let library = makeModInfo(uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let imported = makeModInfo(uuid: "new", dependencies: [makeDependency(uuid: library.uuid.uppercased())])
        XCTAssertFalse(report([imported], active: [library]).findings.contains { $0.category == .missingDependency })
    }

    func testSERequirementIsReportedForInactiveImportedMods() {
        let imported = makeModInfo(uuid: "new", requiresScriptExtender: true)
        let result = report([imported], seStatus: makeSEStatus(isDeployed: false))
        XCTAssertEqual(result.criticalCount, 1)
        XCTAssertEqual(result.findings.first?.category, .seRequired)
        XCTAssertFalse(report([imported], seStatus: makeSEStatus(isDeployed: true)).findings.contains { $0.category == .seRequired })
    }

    func testPhysicalDuplicatesAreReportedEvenWithOneCanonicalMod() throws {
        let old = makeModInfo(uuid: "same", pakFileName: "Old.pak")
        let imported = makeModInfo(uuid: "same", pakFileName: "New.pak")
        let result = report([imported], active: [old], duplicates: [[old, imported]])
        let finding = try XCTUnwrap(result.findings.first { $0.category == .duplicateUUID })
        XCTAssertTrue(finding.detail.contains("Old.pak"))
        XCTAssertTrue(finding.detail.contains("New.pak"))
        XCTAssertEqual(finding.severity, .critical)
    }

    func testReplacementStillGetsDependencyChecksWithoutNewActivationCandidates() {
        let imported = makeModInfo(uuid: "existing", dependencies: [makeDependency(uuid: "missing")])
        let result = report([imported], candidates: [], replaced: 1)
        XCTAssertTrue(result.activationCandidates.isEmpty)
        XCTAssertEqual(result.replacedFileCount, 1)
        XCTAssertEqual(result.findings.filter { $0.category == .missingDependency }.count, 1)
    }

    func testUnrelatedProblemsAreExcludedAndErrorsAreRetained() {
        let imported = makeModInfo(uuid: "new")
        let broken = makeModInfo(uuid: "unrelated", dependencies: [makeDependency(uuid: "missing")], requiresScriptExtender: true)
        let result = report([imported], active: [broken], errors: ["Other.zip: invalid PAK"])
        XCTAssertTrue(result.findings.isEmpty)
        XCTAssertEqual(result.importErrors, ["Other.zip: invalid PAK"])
    }

    func testMetadataAndLoadOrderAdviceAreScopedToImport() {
        let dependency = makeModInfo(uuid: "dep")
        let imported = makeModInfo(uuid: "new", dependencies: [makeDependency(uuid: "dep")], metadataSource: .filename)
        let result = report([imported, dependency])
        XCTAssertTrue(result.findings.contains { $0.category == .noMetadata && $0.severity == .info })
        XCTAssertTrue(result.findings.contains { $0.category == .wrongLoadOrder && $0.suggestedAction == .autoSort })
    }

    @MainActor
    func testActivationIsOneUndoableActionAndKeepingInactiveDoesNotChangeOrder() {
        let existing = makeModInfo(uuid: "existing")
        let a = makeModInfo(uuid: "a")
        let b = makeModInfo(uuid: "b")
        let unrelated = makeModInfo(uuid: "unrelated")
        let state = AppState(nexusCredentialStore: TestNexusCredentialStore())
        state.activeMods = [existing]
        state.inactiveMods = [a, unrelated, b]
        let review = report([a, b], active: [existing])
        state.importHealthReport = review
        state.finishImportHealthReview(activate: false)
        XCTAssertEqual(state.activeMods, [existing])
        XCTAssertEqual(state.inactiveMods, [a, unrelated, b])
        XCTAssertFalse(state.hasUnsavedChanges)
        state.importHealthReport = review
        state.finishImportHealthReview(activate: true)
        XCTAssertEqual(state.activeMods.map(\.uuid), ["existing", "a", "b"])
        XCTAssertEqual(state.inactiveMods, [unrelated])
        XCTAssertTrue(state.hasUnsavedChanges)
        state.undo()
        XCTAssertEqual(state.activeMods, [existing])
        XCTAssertEqual(state.inactiveMods, [a, unrelated, b])
        XCTAssertFalse(state.canUndo)
    }

    @MainActor
    func testDuplicateFollowupWaitsUntilReviewDismisses() {
        let a = makeModInfo(uuid: "same", pakFileName: "A.pak")
        let b = makeModInfo(uuid: "same", pakFileName: "B.pak")
        let state = AppState(nexusCredentialStore: TestNexusCredentialStore())
        state.duplicateGroups = [[a, b]]
        state.importHealthReport = report([b], duplicates: [[a, b]])
        state.finishImportHealthReview(activate: false, followup: "duplicates")
        XCTAssertFalse(state.showDuplicateResolver)
        state.completeImportHealthDismissal()
        XCTAssertTrue(state.showDuplicateResolver)
    }

    private func report(
        _ imported: [ModInfo], candidates: [ModInfo]? = nil,
        active: [ModInfo] = [], inactive: [ModInfo] = [], duplicates: [[ModInfo]] = [],
        seStatus: ScriptExtenderService.SEStatus? = nil, replaced: Int = 0, errors: [String] = []
    ) -> ImportHealthReport {
        ImportHealthService().report(
            importedMods: imported, activationCandidates: candidates ?? imported,
            activeMods: active, inactiveMods: inactive + imported,
            duplicateGroups: duplicates, seStatus: seStatus, loadOrderRules: [],
            replacedFileCount: replaced, importErrors: errors
        )
    }
}
