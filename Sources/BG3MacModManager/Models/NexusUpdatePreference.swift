// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// User-controlled suppression for Nexus version comparisons that do not map
/// cleanly to a mod page's primary file (for example optional or alternate files).
struct NexusUpdatePreference: Codable, Equatable, Sendable {
    var ignoredVersion: String?
    var ignoredNexusModID: Int?
    var checksDisabled: Bool
    var updatedAt: Date

    static func enabled(now: Date = Date()) -> NexusUpdatePreference {
        NexusUpdatePreference(
            ignoredVersion: nil,
            ignoredNexusModID: nil,
            checksDisabled: false,
            updatedAt: now
        )
    }

    func suppresses(_ result: NexusUpdateResult) -> Bool {
        if checksDisabled { return true }
        guard ignoredNexusModID == result.nexusModID,
              let ignoredVersion else { return false }
        return Self.normalized(ignoredVersion) == Self.normalized(result.latestVersion)
    }

    var isEmpty: Bool {
        !checksDisabled && ignoredVersion == nil && ignoredNexusModID == nil
    }

    private static func normalized(_ value: String) -> String {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("v") { normalized.removeFirst() }
        if let version = Version64(versionString: normalized) {
            return String(version.rawValue)
        }
        return normalized
    }
}

struct NexusUpdatePreferencePayload: Codable, Equatable {
    var preferencesByUUID: [String: NexusUpdatePreference]
}
