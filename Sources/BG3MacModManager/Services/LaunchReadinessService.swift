// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

actor LaunchReadinessService {
    private struct FileFingerprint: Equatable, Sendable {
        let size: Int64
        let modifiedAt: Date
    }

    private struct CachedInspection: Sendable {
        let fingerprint: FileFingerprint
        let finding: ReadinessFinding?
    }

    private var fileInspectionCache: [String: CachedInspection] = [:]
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func evaluate(_ snapshot: LaunchReadinessSnapshot) async -> LaunchReadinessReport {
        var findings = snapshot.validationWarnings.map(Self.finding(from:))
        var fingerprintComponents = snapshot.activeMods.map {
            "\(ModIdentity.comparisonKey($0.uuid)):\($0.pakFilePath?.standardizedFileURL.path ?? "missing")"
        }

        for mod in snapshot.activeMods where !mod.isBasicGameModule {
            let inspection = inspectFile(for: mod)
            if let finding = inspection.finding { findings.append(finding) }
            fingerprintComponents.append(inspection.fingerprintDescription)
        }

        if snapshot.hasUnsavedChanges {
            findings.append(Self.makeFinding(
                severity: .warning,
                category: .files,
                title: "Load order has unsaved changes",
                detail: "The game will continue using the previous modsettings.lsx until the current order is saved.",
                action: .saveLoadOrder
            ))
        }

        if snapshot.externalModSettingsChangeDetected {
            findings.append(Self.makeFinding(
                severity: .warning,
                category: .files,
                title: "modsettings.lsx changed outside the app",
                detail: "Review or restore the external change before relying on the displayed load order.",
                action: .restoreModSettings
            ))
        }

        if !snapshot.modSettingsExists && snapshot.activeMods.contains(where: { !$0.isBasicGameModule }) {
            findings.append(Self.makeFinding(
                severity: .warning,
                category: .files,
                title: "modsettings.lsx does not exist",
                detail: "Save the active load order before launching with mods.",
                action: .saveLoadOrder
            ))
        }

        if !snapshot.gameInstalled {
            findings.append(Self.makeFinding(
                severity: .critical,
                category: .game,
                title: "Baldur's Gate 3 was not found",
                detail: "The configured Steam installation does not contain the game app.",
                action: nil
            ))
        } else if !snapshot.steamRunning {
            findings.append(Self.makeFinding(
                severity: .information,
                category: .game,
                title: "Steam is not running",
                detail: "Steam should start when the game URL is opened; launch may take longer.",
                action: nil
            ))
        }

        if snapshot.gameRunning {
            findings.append(Self.makeFinding(
                severity: .warning,
                category: .game,
                title: "Baldur's Gate 3 is already running",
                detail: "Changes made after the game started will not be loaded until it is restarted.",
                action: nil
            ))
        }

        var checks = [
            ReadinessCheckStatus(id: "validation", name: "Load order and validation", state: .completed, detail: nil),
            ReadinessCheckStatus(id: "files", name: "Installed PAK files", state: .completed, detail: nil),
            ReadinessCheckStatus(id: "game", name: "Game and Script Extender", state: .completed, detail: nil),
            ReadinessCheckStatus(id: "saves", name: "Save and profile association", state: .completed, detail: nil),
        ]

        checks.append(contentsOf: nexusStatusAndFindings(snapshot: snapshot, findings: &findings))
        findings.append(contentsOf: snapshot.additionalFindings)
        findings = deduplicated(findings).sorted(by: Self.findingOrder)

        fingerprintComponents.append(contentsOf: findings.map(\.id))
        fingerprintComponents.append("unsaved:\(snapshot.hasUnsavedChanges)")
        fingerprintComponents.append("external:\(snapshot.externalModSettingsChangeDetected)")
        fingerprintComponents.append("game:\(snapshot.gameInstalled):\(snapshot.gameRunning)")
        let snapshotID = Self.sha256(fingerprintComponents.joined(separator: "|"))

        return LaunchReadinessReport(
            snapshotID: snapshotID,
            generatedAt: now(),
            findings: findings,
            checks: checks
        )
    }

    private func inspectFile(for mod: ModInfo) -> (finding: ReadinessFinding?, fingerprintDescription: String) {
        guard let url = mod.pakFilePath else {
            if mod.metadataSource == .modSettings { return (nil, "phantom:\(mod.uuid)") }
            return (Self.makeFinding(
                severity: .critical,
                category: .files,
                title: "Missing PAK: \(mod.name)",
                detail: "The active mod has no installed PAK path.",
                affectedModUUIDs: [mod.uuid],
                action: .openModsFolder
            ), "missing:\(mod.uuid)")
        }

        let path = url.standardizedFileURL.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = (attributes[.size] as? NSNumber)?.int64Value,
              let modifiedAt = attributes[.modificationDate] as? Date else {
            return (Self.makeFinding(
                severity: .critical,
                category: .files,
                title: "Missing PAK: \(mod.name)",
                detail: "No readable file was found at \(path).",
                affectedModUUIDs: [mod.uuid],
                affectedPaths: [url],
                action: .openModsFolder
            ), "missing-path:\(path)")
        }

        let fingerprint = FileFingerprint(size: size, modifiedAt: modifiedAt)
        if let cached = fileInspectionCache[path], cached.fingerprint == fingerprint {
            return (cached.finding, "\(path):\(size):\(modifiedAt.timeIntervalSince1970)")
        }

        let finding: ReadinessFinding?
        if !FileManager.default.isReadableFile(atPath: path) {
            finding = Self.makeFinding(
                severity: .critical,
                category: .files,
                title: "Unreadable PAK: \(mod.name)",
                detail: "The app cannot read \(path).",
                affectedModUUIDs: [mod.uuid],
                affectedPaths: [url],
                action: .openModsFolder
            )
        } else {
            do {
                _ = try PakReader.listFiles(at: url)
                finding = nil
            } catch {
                finding = Self.makeFinding(
                    severity: .critical,
                    category: .files,
                    title: "Invalid PAK: \(mod.name)",
                    detail: error.localizedDescription,
                    affectedModUUIDs: [mod.uuid],
                    affectedPaths: [url],
                    action: .openModsFolder
                )
            }
        }

        fileInspectionCache[path] = CachedInspection(fingerprint: fingerprint, finding: finding)
        return (finding, "\(path):\(size):\(modifiedAt.timeIntervalSince1970)")
    }

    private func nexusStatusAndFindings(
        snapshot: LaunchReadinessSnapshot,
        findings: inout [ReadinessFinding]
    ) -> [ReadinessCheckStatus] {
        if snapshot.nexusCheckInProgress {
            return [ReadinessCheckStatus(
                id: "nexus",
                name: "Nexus update status",
                state: .skipped,
                detail: "An update check is currently running."
            )]
        }
        guard snapshot.nexusConfigured else {
            return [ReadinessCheckStatus(
                id: "nexus",
                name: "Nexus update status",
                state: .unavailable,
                detail: "No Nexus credential is configured. This does not affect launch safety."
            )]
        }
        guard !snapshot.nexusResults.isEmpty else {
            return [ReadinessCheckStatus(
                id: "nexus",
                name: "Nexus update status",
                state: .stale,
                detail: "No completed update results are available."
            )]
        }

        let latestCheck = snapshot.nexusResults.map(\.checkedDate).max() ?? .distantPast
        let isStale = now().timeIntervalSince(latestCheck) > NexusAPIService.cacheMaxAge
        let changed = snapshot.nexusResults.filter {
            ($0.hasUpdate || $0.versionDiffers)
                && !snapshot.suppressedNexusResultIDs.contains(
                    ModIdentity.comparisonKey($0.modUUID)
                )
        }
        if !changed.isEmpty {
            findings.append(Self.makeFinding(
                severity: .information,
                category: .updates,
                title: "\(changed.count) mod version\(changed.count == 1 ? "" : "s") differ from Nexus",
                detail: "Updates are advisory and do not block launch. Review the update list when convenient.",
                affectedModUUIDs: changed.map(\.modUUID),
                action: .viewUpdates
            ))
        }
        return [ReadinessCheckStatus(
            id: "nexus",
            name: "Nexus update status",
            state: isStale ? .stale : .completed,
            detail: isStale ? "The latest cached check is older than one hour." : nil
        )]
    }

    private func deduplicated(_ findings: [ReadinessFinding]) -> [ReadinessFinding] {
        var seen = Set<String>()
        return findings.filter { seen.insert($0.id).inserted }
    }

    private static func finding(from warning: ModWarning) -> ReadinessFinding {
        let severity: ReadinessSeverity
        switch warning.severity {
        case .critical: severity = .critical
        case .warning: severity = .warning
        case .info: severity = .information
        }

        let category: ReadinessCategory
        switch warning.category {
        case .duplicateUUID, .phantomMod, .noMetadata, .externalModSettingsChange:
            category = .files
        case .missingDependency, .wrongLoadOrder, .circularDependency, .conflictingMods, .loadOrderRule:
            category = .order
        case .seRequired, .modCrashSanityCheck, .seDisappeared:
            category = .game
        }

        let action: ReadinessAction?
        switch warning.suggestedAction {
        case .autoSort: action = .smartSort
        case .deactivateMod(let uuid): action = .deactivateMod(uuid)
        case .activateDependencies(let uuid): action = .activateDependencies(uuid)
        case .deleteModCrashSanityCheck: action = .deleteModCrashSanityCheck
        case .restoreModSettings: action = .restoreModSettings
        case .installScriptExtender, .viewSEStatus: action = .viewScriptExtender
        case .installDependency, .none: action = nil
        }

        return makeFinding(
            severity: severity,
            category: category,
            title: warning.message,
            detail: warning.detail,
            affectedModUUIDs: warning.affectedModUUIDs,
            action: action
        )
    }

    private static func makeFinding(
        severity: ReadinessSeverity,
        category: ReadinessCategory,
        title: String,
        detail: String,
        affectedModUUIDs: [String] = [],
        affectedPaths: [URL] = [],
        action: ReadinessAction?
    ) -> ReadinessFinding {
        let normalizedUUIDs = affectedModUUIDs.map(ModIdentity.comparisonKey).sorted()
        let paths = affectedPaths.map { $0.standardizedFileURL.path }.sorted()
        let id = sha256(
            "\(severity.rawValue)|\(category.rawValue)|\(title)|\(detail)|\(normalizedUUIDs.joined(separator: ","))|\(paths.joined(separator: ","))"
        )
        return ReadinessFinding(
            id: id,
            severity: severity,
            category: category,
            title: title,
            detail: detail,
            affectedModUUIDs: normalizedUUIDs,
            affectedPaths: affectedPaths,
            action: action
        )
    }

    private static func findingOrder(_ lhs: ReadinessFinding, _ rhs: ReadinessFinding) -> Bool {
        if lhs.severity != rhs.severity { return lhs.severity > rhs.severity }
        if lhs.category.rawValue != rhs.category.rawValue {
            return lhs.category.rawValue < rhs.category.rawValue
        }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
