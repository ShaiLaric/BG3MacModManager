// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Persists per-mod Nexus Mods URLs to a JSON file.
/// Follows the same persistence pattern as CategoryInferenceService.
final class NexusURLService {

    // MARK: - Public API

    /// Get the stored Nexus URL for a mod, if any.
    func url(for modUUID: String) -> String? {
        urls[ModIdentity.comparisonKey(modUUID)]
    }

    /// Set or update the Nexus URL for a mod. Pass nil or empty string to clear.
    @discardableResult
    func setURL(_ url: String?, for modUUID: String) -> Bool {
        let previous = urls
        let modUUID = ModIdentity.comparisonKey(modUUID)
        if let url = url, !url.isEmpty {
            urls[modUUID] = url
        } else {
            urls.removeValue(forKey: modUUID)
        }
        do {
            try save()
            return true
        } catch {
            urls = previous
            return false
        }
    }

    /// All stored URLs (for bulk lookup during import).
    func allURLs() -> [String: String] {
        urls
    }

    /// Set multiple URLs at once (for bulk import operations).
    /// Each key is a mod UUID, each value is the Nexus URL.
    @discardableResult
    func bulkSetURLs(_ newURLs: [String: String]) -> Bool {
        let previous = urls
        for (uuid, url) in newURLs {
            let uuid = ModIdentity.comparisonKey(uuid)
            if url.isEmpty {
                urls.removeValue(forKey: uuid)
            } else {
                urls[uuid] = url
            }
        }
        do {
            try save()
            return true
        } catch {
            urls = previous
            return false
        }
    }

    // MARK: - Persistence

    private var urls: [String: String] = [:]

    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL
            ?? FileLocations.appSupportDirectory.appendingPathComponent("nexus_urls.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        urls = Dictionary(
            decoded.map { (ModIdentity.comparisonKey($0.key), $0.value) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    private func save() throws {
        try FileLocations.ensureDirectoryExists(storageURL.deletingLastPathComponent())
        let data = try JSONEncoder().encode(urls)
        try data.write(to: storageURL, options: .atomic)
    }
}
