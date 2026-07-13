// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Cached result of checking a mod's update status on Nexus Mods.
struct NexusUpdateResult: Codable, Identifiable, Sendable {
    let modUUID: String
    let nexusModID: Int
    let installedVersion: String
    let latestVersion: String
    let latestName: String
    let updatedDate: Date?
    let nexusURL: String
    let checkedDate: Date

    var id: String { modUUID }

    enum VersionStatus {
        case current
        case newerAvailable
        case versionDiffers
    }

    var versionStatus: VersionStatus {
        let installed = normalizedVersion(installedVersion)
        let latest = normalizedVersion(latestVersion)
        guard !latestVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .current
        }
        if let installed, let latest {
            if latest == installed { return .current }
            return latest > installed ? .newerAvailable : .versionDiffers
        }
        return latestVersion.caseInsensitiveCompare(installedVersion) == .orderedSame
            ? .current
            : .versionDiffers
    }

    /// True only when both values can be ordered and Nexus reports a newer version.
    var hasUpdate: Bool {
        versionStatus == .newerAvailable
    }

    var versionDiffers: Bool {
        versionStatus == .versionDiffers
    }

    private func normalizedVersion(_ value: String) -> Version64? {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("v") { normalized.removeFirst() }
        let parts = normalized.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty,
              parts.count <= 4,
              parts.allSatisfy({ !$0.isEmpty && Int($0) != nil }) else { return nil }
        return Version64(versionString: normalized)
    }
}

struct NexusUpdateCandidate: Sendable {
    let modUUID: String
    let installedVersion: String
    let nexusURL: String
}

struct NexusUpdateCheckReport: Sendable {
    let results: [String: NexusUpdateResult]
    let checkedCount: Int
    let cachedCount: Int
    let failedCount: Int
    let skippedCount: Int
    let rateLimited: Bool
    let totalCount: Int
    let cachePersisted: Bool

    var isComplete: Bool {
        !rateLimited && skippedCount == 0 && failedCount == 0
            && checkedCount + cachedCount == totalCount
    }
}

/// Cache container persisted to disk.
struct NexusUpdateCache: Codable {
    var results: [String: NexusUpdateResult] = [:]
    var lastFullCheck: Date?
}
