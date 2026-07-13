// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum ReadinessSeverity: Int, Codable, Comparable, CaseIterable, Sendable {
    case information = 1
    case warning = 2
    case critical = 3

    static func < (lhs: ReadinessSeverity, rhs: ReadinessSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum ReadinessCategory: String, Codable, CaseIterable, Sendable {
    case files = "Files"
    case order = "Order & Dependencies"
    case game = "Game & Script Extender"
    case saves = "Saves & Profiles"
    case updates = "Updates"
}

enum ReadinessAction: Equatable, Sendable {
    case refresh
    case saveLoadOrder
    case smartSort
    case deactivateMod(String)
    case activateDependencies(String)
    case deleteModCrashSanityCheck
    case restoreModSettings
    case viewScriptExtender
    case openModsFolder
    case manageRules
    case viewUpdates
    case viewSaves
    case loadProfile(UUID)

    var title: String {
        switch self {
        case .refresh: return "Refresh"
        case .saveLoadOrder: return "Save"
        case .smartSort: return "Sort"
        case .deactivateMod: return "Deactivate"
        case .activateDependencies: return "Activate Dependencies"
        case .deleteModCrashSanityCheck: return "Remove Folder"
        case .restoreModSettings: return "Restore"
        case .viewScriptExtender: return "View SE Status"
        case .openModsFolder: return "Open Mods Folder"
        case .manageRules: return "Manage Rules"
        case .viewUpdates: return "View Updates"
        case .viewSaves: return "View Saves"
        case .loadProfile: return "Load Profile"
        }
    }
}

struct ReadinessFinding: Identifiable, Equatable, Sendable {
    let id: String
    let severity: ReadinessSeverity
    let category: ReadinessCategory
    let title: String
    let detail: String
    let affectedModUUIDs: [String]
    let affectedPaths: [URL]
    let action: ReadinessAction?
}

struct ReadinessCheckStatus: Identifiable, Equatable, Sendable {
    enum State: String, Sendable {
        case completed
        case skipped
        case unavailable
        case stale
    }

    let id: String
    let name: String
    let state: State
    let detail: String?
}

struct LaunchReadinessReport: Identifiable, Equatable, Sendable {
    enum OverallState: String, Sendable {
        case ready = "Ready"
        case review = "Review"
        case critical = "Critical"
    }

    let snapshotID: String
    let generatedAt: Date
    let findings: [ReadinessFinding]
    let checks: [ReadinessCheckStatus]

    var id: String { snapshotID }

    var overallState: OverallState {
        if findings.contains(where: { $0.severity == .critical }) { return .critical }
        if findings.contains(where: { $0.severity == .warning }) { return .review }
        return .ready
    }

    var criticalFindings: [ReadinessFinding] {
        findings.filter { $0.severity == .critical }
    }

    var diagnosticSummary: String {
        var lines = [
            "BG3 Mac Mod Manager — Launch Readiness",
            "State: \(overallState.rawValue)",
            "Generated: \(ISO8601DateFormatter().string(from: generatedAt))",
            "Snapshot: \(snapshotID)",
        ]
        for finding in findings {
            lines.append("[\(finding.severity)] [\(finding.category.rawValue)] \(finding.title): \(finding.detail)")
        }
        for check in checks where check.state != .completed {
            lines.append("[check \(check.state.rawValue)] \(check.name): \(check.detail ?? "")")
        }
        return lines.joined(separator: "\n")
    }
}

struct LaunchReadinessSnapshot: Sendable {
    let activeMods: [ModInfo]
    let inactiveMods: [ModInfo]
    let validationWarnings: [ModWarning]
    let hasUnsavedChanges: Bool
    let externalModSettingsChangeDetected: Bool
    let modSettingsExists: Bool
    let gameInstalled: Bool
    let steamRunning: Bool
    let gameRunning: Bool
    let nexusConfigured: Bool
    let nexusCheckInProgress: Bool
    let nexusResults: [NexusUpdateResult]
    let suppressedNexusResultIDs: Set<String>
    let additionalFindings: [ReadinessFinding]

    init(
        activeMods: [ModInfo],
        inactiveMods: [ModInfo],
        validationWarnings: [ModWarning],
        hasUnsavedChanges: Bool,
        externalModSettingsChangeDetected: Bool,
        modSettingsExists: Bool,
        gameInstalled: Bool,
        steamRunning: Bool,
        gameRunning: Bool,
        nexusConfigured: Bool,
        nexusCheckInProgress: Bool,
        nexusResults: [NexusUpdateResult],
        suppressedNexusResultIDs: Set<String> = [],
        additionalFindings: [ReadinessFinding] = []
    ) {
        self.activeMods = activeMods
        self.inactiveMods = inactiveMods
        self.validationWarnings = validationWarnings
        self.hasUnsavedChanges = hasUnsavedChanges
        self.externalModSettingsChangeDetected = externalModSettingsChangeDetected
        self.modSettingsExists = modSettingsExists
        self.gameInstalled = gameInstalled
        self.steamRunning = steamRunning
        self.gameRunning = gameRunning
        self.nexusConfigured = nexusConfigured
        self.nexusCheckInProgress = nexusCheckInProgress
        self.nexusResults = nexusResults
        self.suppressedNexusResultIDs = suppressedNexusResultIDs
        self.additionalFindings = additionalFindings
    }
}
