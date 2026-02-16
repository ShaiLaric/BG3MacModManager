// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Interfaces with the Nexus Mods API v1 to check for mod updates.
/// Requires a personal API key configured in Settings.
final class NexusAPIService {

    // MARK: - Types

    enum APIError: Error, LocalizedError {
        case noAPIKey
        case invalidModID
        case rateLimited
        case httpError(Int)
        case networkError(Error)
        case decodingError(Error)

        var errorDescription: String? {
            switch self {
            case .noAPIKey:
                return "No Nexus Mods API key configured. Set one in Settings."
            case .invalidModID:
                return "Could not extract a mod ID from the Nexus URL."
            case .rateLimited:
                return "Nexus API rate limit reached. Try again later."
            case .httpError(let code):
                return "Nexus API returned HTTP \(code)."
            case .networkError(let err):
                return "Network error: \(err.localizedDescription)"
            case .decodingError(let err):
                return "Failed to parse Nexus API response: \(err.localizedDescription)"
            }
        }
    }

    /// Subset of fields from the Nexus Mods API /mods/{id}.json response.
    struct NexusModResponse: Codable {
        let name: String
        let version: String
        let updated_timestamp: Int?
        let available: Bool?

        var updatedDate: Date? {
            guard let ts = updated_timestamp else { return nil }
            return Date(timeIntervalSince1970: TimeInterval(ts))
        }
    }

    // MARK: - Configuration

    private let baseURL = "https://api.nexusmods.com/v1"
    private let gameDomain = "baldursgate3"
    private let session: URLSession

    /// Minimum interval between API requests (to respect rate limits).
    private let requestInterval: TimeInterval = 1.0

    /// Maximum age of a cached result before re-checking (in seconds).
    static let cacheMaxAge: TimeInterval = 3600 // 1 hour

    // MARK: - Cache

    private var cache: NexusUpdateCache

    private static var cacheURL: URL {
        FileLocations.appSupportDirectory.appendingPathComponent("nexus_update_cache.json")
    }

    // MARK: - Initialization

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
        cache = Self.loadCache()
    }

    // MARK: - Public API

    /// Get the API key from UserDefaults.
    var apiKey: String? {
        let key = UserDefaults.standard.string(forKey: "nexusAPIKey")
        return (key?.isEmpty == false) ? key : nil
    }

    /// Check for updates for all mods that have Nexus URLs.
    /// Returns a dictionary of UUID -> NexusUpdateResult.
    func checkForUpdates(
        mods: [ModInfo],
        nexusURLService: NexusURLService,
        progress: @escaping (Int, Int) -> Void
    ) async throws -> [String: NexusUpdateResult] {
        guard let apiKey = apiKey else { throw APIError.noAPIKey }

        let modsWithURLs = mods.compactMap { mod -> (ModInfo, String, Int)? in
            guard let urlString = nexusURLService.url(for: mod.uuid),
                  let modID = extractModID(from: urlString) else {
                return nil
            }
            return (mod, urlString, modID)
        }

        var results: [String: NexusUpdateResult] = cache.results
        let total = modsWithURLs.count
        var checked = 0

        for (mod, urlString, modID) in modsWithURLs {
            // Skip if recently checked
            if let cached = cache.results[mod.uuid],
               Date().timeIntervalSince(cached.checkedDate) < Self.cacheMaxAge {
                checked += 1
                progress(checked, total)
                continue
            }

            // Rate limiting: wait between requests
            if checked > 0 {
                try await Task.sleep(nanoseconds: UInt64(requestInterval * 1_000_000_000))
            }

            do {
                let response = try await fetchModInfo(modID: modID, apiKey: apiKey)
                let result = NexusUpdateResult(
                    modUUID: mod.uuid,
                    nexusModID: modID,
                    installedVersion: mod.version.description,
                    latestVersion: response.version,
                    latestName: response.name,
                    updatedDate: response.updatedDate,
                    nexusURL: urlString,
                    checkedDate: Date()
                )
                results[mod.uuid] = result
            } catch APIError.rateLimited {
                // Stop checking on rate limit
                break
            } catch {
                // Log but continue with other mods
            }

            checked += 1
            progress(checked, total)
        }

        cache.results = results
        cache.lastFullCheck = Date()
        saveCache()

        return results
    }

    /// Get cached result for a specific mod.
    func cachedResult(for modUUID: String) -> NexusUpdateResult? {
        cache.results[modUUID]
    }

    /// Clear all cached update data.
    func clearCache() {
        cache = NexusUpdateCache()
        saveCache()
    }

    // MARK: - API Calls

    private func fetchModInfo(modID: Int, apiKey: String) async throws -> NexusModResponse {
        guard let url = URL(string: "\(baseURL)/games/\(gameDomain)/mods/\(modID).json") else {
            throw APIError.invalidModID
        }

        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.httpError(0)
        }

        if httpResponse.statusCode == 429 {
            throw APIError.rateLimited
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(NexusModResponse.self, from: data)
        } catch {
            throw APIError.decodingError(error)
        }
    }

    // MARK: - Helpers

    /// Extract numeric mod ID from Nexus URL.
    func extractModID(from url: String) -> Int? {
        let pattern = #"/mods/(\d+)"#
        guard let range = url.range(of: pattern, options: .regularExpression) else { return nil }
        let matched = url[range]
        guard let numRange = matched.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(matched[numRange])
    }

    // MARK: - Cache Persistence

    private static func loadCache() -> NexusUpdateCache {
        guard let data = try? Data(contentsOf: cacheURL) else {
            return NexusUpdateCache()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let decoded = try? decoder.decode(NexusUpdateCache.self, from: data) else {
            return NexusUpdateCache()
        }
        return decoded
    }

    private func saveCache() {
        do {
            try FileLocations.ensureDirectoryExists(FileLocations.appSupportDirectory)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: Self.cacheURL, options: .atomic)
        } catch {
            // Non-fatal: cache just won't persist
        }
    }
}
