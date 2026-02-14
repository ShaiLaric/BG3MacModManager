// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Persists per-mod Nexus Mods URLs to a JSON file.
/// Follows the same persistence pattern as CategoryInferenceService.
final class NexusURLService {

    // MARK: - Public API

    /// Get the stored Nexus URL for a mod, if any.
    func url(for modUUID: String) -> String? {
        urls[modUUID]
    }

    /// Set or update the Nexus URL for a mod. Pass nil or empty string to clear.
    func setURL(_ url: String?, for modUUID: String) {
        if let url = url, !url.isEmpty {
            urls[modUUID] = url
        } else {
            urls.removeValue(forKey: modUUID)
        }
        save()
    }

    /// All stored URLs (for bulk lookup during import).
    func allURLs() -> [String: String] {
        urls
    }

    // MARK: - Persistence

    private var urls: [String: String] = [:]

    private static var storageURL: URL {
        FileLocations.appSupportDirectory.appendingPathComponent("nexus_urls.json")
    }

    init() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        urls = decoded
    }

    private func save() {
        do {
            try FileLocations.ensureDirectoryExists(FileLocations.appSupportDirectory)
            let data = try JSONEncoder().encode(urls)
            try data.write(to: Self.storageURL, options: .atomic)
        } catch {
            // Non-fatal: URLs just won't persist
        }
    }
}
