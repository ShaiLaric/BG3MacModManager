// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

actor SaveGameScanner {
    private struct CacheEntry {
        let size: Int64
        let modifiedAt: Date
        let summary: SaveGameSummary
    }

    private let storyDirectory: URL
    private var cache: [String: CacheEntry] = [:]

    init(storyDirectory: URL = FileLocations.savegamesFolder) {
        self.storyDirectory = storyDirectory.standardizedFileURL
    }

    func inspectSave(at url: URL) throws -> SaveGameSummary {
        let values = try url.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey,
        ])
        return inspect(
            url: url,
            size: Int64(values.fileSize ?? 0),
            modifiedAt: values.contentModificationDate ?? .distantPast,
            resourceIdentity: values.fileResourceIdentifier.map { String(describing: $0) }
        )
    }

    func scan() throws -> [SaveGameSummary] {
        guard FileManager.default.fileExists(atPath: storyDirectory.path) else { return [] }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .fileResourceIdentifierKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: storyDirectory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var summaries: [SaveGameSummary] = []
        var livePaths = Set<String>()
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            guard url.pathExtension.caseInsensitiveCompare("lsv") == .orderedSame else { continue }
            let values = try url.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }

            let size = Int64(values.fileSize ?? 0)
            let modifiedAt = values.contentModificationDate ?? .distantPast
            let path = url.standardizedFileURL.path
            livePaths.insert(path)
            if let cached = cache[path], cached.size == size, cached.modifiedAt == modifiedAt {
                summaries.append(cached.summary)
                continue
            }

            let summary = inspect(
                url: url,
                size: size,
                modifiedAt: modifiedAt,
                resourceIdentity: values.fileResourceIdentifier.map { String(describing: $0) }
            )
            cache[path] = CacheEntry(size: size, modifiedAt: modifiedAt, summary: summary)
            summaries.append(summary)
        }

        cache = cache.filter { livePaths.contains($0.key) }
        return summaries.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func inspect(
        url: URL,
        size: Int64,
        modifiedAt: Date,
        resourceIdentity: String?
    ) -> SaveGameSummary {
        let relativePath = relativePath(for: url)
        let folderName = url.deletingLastPathComponent().lastPathComponent
        let campaignName = Self.campaignName(from: folderName)
        let saveIDSeed = resourceIdentity.map { "resource:\($0)" } ?? "path:\(relativePath.lowercased())"
        let saveID = Self.sha256(saveIDSeed)
        let screenshotURL = siblingScreenshot(for: url)

        do {
            let archive = try SaveGameArchiveReader().read(from: url)
            let mods = archive.mods
            let campaignIdentity = archive.gameID.flatMap { value -> String? in
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized.isEmpty ? nil : "game-id:\(normalized)"
            }
                ?? "campaign-name:\(campaignName.lowercased())"
            let campaignID = Self.sha256(campaignIdentity)
            let fingerprint = Self.sha256(mods.map {
                "\($0.uuid):\($0.version64):\($0.md5)"
            }.joined(separator: "|"))
            return SaveGameSummary(
                id: saveID,
                campaignID: campaignID,
                campaignName: campaignName,
                displayName: url.deletingPathExtension().lastPathComponent,
                relativePath: relativePath,
                fileURL: url,
                screenshotURL: screenshotURL,
                modifiedAt: modifiedAt,
                fileSize: size,
                fileResourceIdentity: resourceIdentity,
                mods: mods,
                modListFingerprint: fingerprint,
                readError: nil
            )
        } catch {
            let campaignID = Self.normalizedIdentity(campaignName)
            return SaveGameSummary(
                id: saveID,
                campaignID: campaignID,
                campaignName: campaignName,
                displayName: url.deletingPathExtension().lastPathComponent,
                relativePath: relativePath,
                fileURL: url,
                screenshotURL: screenshotURL,
                modifiedAt: modifiedAt,
                fileSize: size,
                fileResourceIdentity: resourceIdentity,
                mods: [],
                modListFingerprint: nil,
                readError: error.localizedDescription
            )
        }
    }

    private func relativePath(for url: URL) -> String {
        let base = storyDirectory.path.hasSuffix("/") ? storyDirectory.path : storyDirectory.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : url.lastPathComponent
    }

    private func siblingScreenshot(for url: URL) -> URL? {
        let base = url.deletingPathExtension()
        for ext in ["WebP", "webp", "png", "jpg"] {
            let candidate = base.appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    static func campaignName(from folderName: String) -> String {
        let prefix = folderName.components(separatedBy: "__").first ?? folderName
        guard let range = prefix.range(of: #"-\d+$"#, options: .regularExpression) else {
            return prefix
        }
        let name = String(prefix[..<range.lowerBound])
        return name.isEmpty ? prefix : name
    }

    private static func normalizedIdentity(_ value: String) -> String {
        let normalized = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sha256("campaign:\(normalized.lowercased())")
    }

    private static func sha256(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

}
