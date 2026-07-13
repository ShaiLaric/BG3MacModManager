// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Interfaces with the Nexus Mods API v1 to check for mod updates.
/// Requires a personal API key configured in Settings.
actor NexusAPIService {

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
    nonisolated let credentialStore: NexusCredentialStore

    /// Minimum interval between API requests (to respect rate limits).
    private let requestInterval: TimeInterval = 1.0

    /// Maximum age of a cached result before re-checking (in seconds).
    static let cacheMaxAge: TimeInterval = 3600 // 1 hour

    // MARK: - Cache

    private var cache: NexusUpdateCache

    private let cacheURL: URL

    // MARK: - Initialization

    init(
        session: URLSession? = nil,
        credentialStore: NexusCredentialStore = NexusCredentialStore(),
        cacheURL: URL = FileLocations.appSupportDirectory
            .appendingPathComponent("nexus_update_cache.json")
    ) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        self.session = session ?? URLSession(configuration: config)
        self.credentialStore = credentialStore
        self.cacheURL = cacheURL
        credentialStore.migrateLegacyValueIfNeeded()
        cache = Self.loadCache(from: cacheURL)
    }

    // MARK: - Public API

    /// Get the API key from the user's Keychain.
    nonisolated var apiKey: String? {
        credentialStore.apiKey()
    }

    /// Check update candidates and return explicit completion/error accounting.
    func checkForUpdates(
        candidates: [NexusUpdateCandidate],
        progress: @escaping @Sendable (Int, Int) -> Void
    ) async throws -> NexusUpdateCheckReport {
        guard let apiKey = apiKey else { throw APIError.noAPIKey }

        let total = candidates.count
        var skipped = 0
        let validCandidates = candidates.compactMap {
            candidate -> (NexusUpdateCandidate, Int)? in
            guard let modID = extractModID(from: candidate.nexusURL) else {
                skipped += 1
                return nil
            }
            return (candidate, modID)
        }

        var results: [String: NexusUpdateResult] = [:]
        var checked = 0
        var cached = 0
        var failed = 0
        var completed = skipped
        var rateLimited = false
        var madeNetworkRequest = false
        progress(completed, total)

        for (candidate, modID) in validCandidates {
            let uuid = ModIdentity.comparisonKey(candidate.modUUID)
            if let cachedResult = cache.results[uuid],
               cachedResult.installedVersion == candidate.installedVersion,
               cachedResult.nexusURL == candidate.nexusURL,
               Date().timeIntervalSince(cachedResult.checkedDate) < Self.cacheMaxAge {
                results[uuid] = cachedResult
                cached += 1
                completed += 1
                progress(completed, total)
                continue
            }

            // Rate limiting: wait between requests
            if madeNetworkRequest {
                try await Task.sleep(nanoseconds: UInt64(requestInterval * 1_000_000_000))
            }
            madeNetworkRequest = true

            do {
                let response = try await fetchModInfo(modID: modID, apiKey: apiKey)
                let result = NexusUpdateResult(
                    modUUID: uuid,
                    nexusModID: modID,
                    installedVersion: candidate.installedVersion,
                    latestVersion: response.version,
                    latestName: response.name,
                    updatedDate: response.updatedDate,
                    nexusURL: candidate.nexusURL,
                    checkedDate: Date()
                )
                results[uuid] = result
                cache.results[uuid] = result
                checked += 1
            } catch APIError.rateLimited {
                rateLimited = true
                break
            } catch {
                failed += 1
            }

            completed += 1
            progress(completed, total)
        }

        if !rateLimited, failed == 0, completed == total {
            cache.lastFullCheck = Date()
        }
        let cachePersisted = saveCache()

        return NexusUpdateCheckReport(
            results: results,
            checkedCount: checked,
            cachedCount: cached,
            failedCount: failed,
            skippedCount: skipped,
            rateLimited: rateLimited,
            totalCount: total,
            cachePersisted: cachePersisted
        )
    }

    /// Get cached result for a specific mod.
    func cachedResult(for modUUID: String) -> NexusUpdateResult? {
        cache.results[modUUID]
    }

    /// Clear all cached update data.
    func clearCache() {
        cache = NexusUpdateCache()
        _ = saveCache()
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
    nonisolated func extractModID(from url: String) -> Int? {
        let pattern = #"/mods/(\d+)"#
        guard let range = url.range(of: pattern, options: .regularExpression) else { return nil }
        let matched = url[range]
        guard let numRange = matched.range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(matched[numRange])
    }

    // MARK: - Cache Persistence

    private static func loadCache(from url: URL) -> NexusUpdateCache {
        guard let data = try? Data(contentsOf: url) else {
            return NexusUpdateCache()
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard var decoded = try? decoder.decode(NexusUpdateCache.self, from: data) else {
            return NexusUpdateCache()
        }
        decoded.results = Dictionary(
            decoded.results.map { (ModIdentity.comparisonKey($0.key), $0.value) },
            uniquingKeysWith: { _, latest in latest }
        )
        return decoded
    }

    @discardableResult
    private func saveCache() -> Bool {
        do {
            try FileLocations.ensureDirectoryExists(FileLocations.appSupportDirectory)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(cache)
            try data.write(to: cacheURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
