// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Cached result of checking a mod's update status on Nexus Mods.
struct NexusUpdateResult: Codable, Identifiable {
    let modUUID: String
    let nexusModID: Int
    let installedVersion: String
    let latestVersion: String
    let latestName: String
    let updatedDate: Date?
    let nexusURL: String
    let checkedDate: Date

    var id: String { modUUID }

    /// Whether the Nexus version differs from the installed version.
    /// Uses simple string comparison — Nexus version strings are free-form text.
    var hasUpdate: Bool {
        !latestVersion.isEmpty &&
        latestVersion.lowercased() != installedVersion.lowercased()
    }
}

/// Cache container persisted to disk.
struct NexusUpdateCache: Codable {
    var results: [String: NexusUpdateResult] = [:]
    var lastFullCheck: Date?
}
