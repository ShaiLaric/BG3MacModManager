// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Parses external files containing mod-to-Nexus-URL mappings and matches
/// them against installed mods for bulk URL population.
final class NexusURLImportService {

    // MARK: - Types

    enum ImportFormat: String {
        case csv = "CSV"
        case tsv = "TSV"
        case json = "JSON"
        case text = "Plain Text"
    }

    enum ImportError: Error, LocalizedError {
        case invalidJSON(String)
        case unknownFormat(String)
        case emptyFile
        case noValidEntries

        var errorDescription: String? {
            switch self {
            case .invalidJSON(let msg): return "Invalid JSON: \(msg)"
            case .unknownFormat(let ext): return "Unrecognized file format: .\(ext)"
            case .emptyFile: return "The imported file is empty"
            case .noValidEntries: return "No valid Nexus Mods URLs found in the file"
            }
        }
    }

    /// A single parsed entry from the import file.
    struct ParsedEntry {
        let identifier: String  // mod name, UUID, or empty
        let nexusURL: String
        let nexusModID: String? // extracted mod ID from URL
    }

    /// A match between a parsed entry and an installed mod.
    struct MatchedEntry: Identifiable {
        let id = UUID()
        let parsedEntry: ParsedEntry
        let matchedMod: ModInfo
        let matchType: MatchType
    }

    enum MatchType: String {
        case uuid = "UUID"
        case exactName = "Exact Name"
        case fuzzyName = "Fuzzy Name"
    }

    /// Result of a bulk URL import operation.
    struct ImportResult {
        let format: ImportFormat
        let totalParsed: Int
        let matched: [MatchedEntry]
        let unmatched: [ParsedEntry]
    }

    // MARK: - Public API

    /// Parse a file and match entries against installed mods.
    func parseAndMatch(
        fileURL: URL,
        installedMods: [ModInfo]
    ) throws -> ImportResult {
        let ext = fileURL.pathExtension.lowercased()
        let entries: [ParsedEntry]
        let format: ImportFormat

        switch ext {
        case "csv":
            entries = try parseCSV(at: fileURL, separator: ",")
            format = .csv
        case "tsv":
            entries = try parseCSV(at: fileURL, separator: "\t")
            format = .tsv
        case "json":
            entries = try parseJSON(at: fileURL)
            format = .json
        case "txt":
            entries = try parsePlainText(at: fileURL)
            format = .text
        default:
            throw ImportError.unknownFormat(ext)
        }

        guard !entries.isEmpty else { throw ImportError.noValidEntries }

        return matchEntries(entries, against: installedMods, format: format)
    }

    /// Parse content from a string (for testing without file I/O).
    func parseAndMatch(
        content: String,
        format: ImportFormat,
        installedMods: [ModInfo]
    ) throws -> ImportResult {
        let entries: [ParsedEntry]

        switch format {
        case .csv:
            entries = parseCSVContent(content, separator: ",")
        case .tsv:
            entries = parseCSVContent(content, separator: "\t")
        case .json:
            entries = try parseJSONContent(content)
        case .text:
            entries = parsePlainTextContent(content)
        }

        guard !entries.isEmpty else { throw ImportError.noValidEntries }

        return matchEntries(entries, against: installedMods, format: format)
    }

    // MARK: - CSV/TSV Parsing

    private func parseCSV(at url: URL, separator: Character) throws -> [ParsedEntry] {
        let content = try String(contentsOf: url, encoding: .utf8)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyFile
        }
        return parseCSVContent(content, separator: separator)
    }

    func parseCSVContent(_ content: String, separator: Character) -> [ParsedEntry] {
        let lines = content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return [] }

        var entries: [ParsedEntry] = []
        let startIndex = looksLikeHeader(lines[0], separator: separator) ? 1 : 0

        for line in lines[startIndex...] {
            let fields = line.split(separator: separator, omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespaces) }

            if fields.count >= 2 {
                // Two-column: identifier + URL
                let identifier = fields[0]
                let url = fields[1]
                if isNexusURL(url) {
                    entries.append(ParsedEntry(
                        identifier: identifier,
                        nexusURL: url,
                        nexusModID: extractModID(from: url)
                    ))
                } else if isNexusURL(identifier) {
                    // Reversed columns: URL first, then identifier
                    entries.append(ParsedEntry(
                        identifier: url,
                        nexusURL: identifier,
                        nexusModID: extractModID(from: identifier)
                    ))
                }
            } else if fields.count == 1 && isNexusURL(fields[0]) {
                // Single column: just URLs
                entries.append(ParsedEntry(
                    identifier: "",
                    nexusURL: fields[0],
                    nexusModID: extractModID(from: fields[0])
                ))
            }
        }

        return entries
    }

    // MARK: - JSON Parsing

    private func parseJSON(at url: URL) throws -> [ParsedEntry] {
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { throw ImportError.emptyFile }
        let content = String(data: data, encoding: .utf8) ?? ""
        return try parseJSONContent(content)
    }

    func parseJSONContent(_ content: String) throws -> [ParsedEntry] {
        guard let data = content.data(using: .utf8) else {
            throw ImportError.invalidJSON("Could not read content as UTF-8")
        }

        // Try array of objects: [{"name": "...", "url": "..."}]
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            let entries = array.compactMap { dict -> ParsedEntry? in
                let url = (dict["url"] as? String)
                    ?? (dict["nexusUrl"] as? String)
                    ?? (dict["nexus_url"] as? String)
                    ?? (dict["nexusURL"] as? String)
                    ?? ""
                guard isNexusURL(url) else { return nil }

                let identifier = (dict["name"] as? String)
                    ?? (dict["modName"] as? String)
                    ?? (dict["mod_name"] as? String)
                    ?? (dict["uuid"] as? String)
                    ?? (dict["UUID"] as? String)
                    ?? ""

                return ParsedEntry(
                    identifier: identifier,
                    nexusURL: url,
                    nexusModID: extractModID(from: url)
                )
            }
            return entries
        }

        // Try dictionary: {"uuid-or-name": "url", ...}
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
            let entries = dict.compactMap { key, value -> ParsedEntry? in
                guard isNexusURL(value) else { return nil }
                return ParsedEntry(
                    identifier: key,
                    nexusURL: value,
                    nexusModID: extractModID(from: value)
                )
            }
            return entries
        }

        throw ImportError.invalidJSON("Expected an array of objects or a string dictionary")
    }

    // MARK: - Plain Text Parsing

    private func parsePlainText(at url: URL) throws -> [ParsedEntry] {
        let content = try String(contentsOf: url, encoding: .utf8)
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ImportError.emptyFile
        }
        return parsePlainTextContent(content)
    }

    func parsePlainTextContent(_ content: String) -> [ParsedEntry] {
        content.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .compactMap { line in
                guard isNexusURL(line) else { return nil }
                return ParsedEntry(
                    identifier: "",
                    nexusURL: line,
                    nexusModID: extractModID(from: line)
                )
            }
    }

    // MARK: - Matching

    private func matchEntries(
        _ entries: [ParsedEntry],
        against mods: [ModInfo],
        format: ImportFormat
    ) -> ImportResult {
        let modsByUUID = Dictionary(
            mods.map { ($0.uuid.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let modsByName = Dictionary(
            mods.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var matched: [MatchedEntry] = []
        var unmatched: [ParsedEntry] = []
        var matchedUUIDs: Set<String> = []

        for entry in entries {
            let id = entry.identifier

            // Try UUID match first
            if !id.isEmpty, let mod = modsByUUID[id.lowercased()], !matchedUUIDs.contains(mod.uuid) {
                matched.append(MatchedEntry(
                    parsedEntry: entry, matchedMod: mod, matchType: .uuid
                ))
                matchedUUIDs.insert(mod.uuid)
                continue
            }

            // Try exact name match
            if !id.isEmpty, let mod = modsByName[id.lowercased()], !matchedUUIDs.contains(mod.uuid) {
                matched.append(MatchedEntry(
                    parsedEntry: entry, matchedMod: mod, matchType: .exactName
                ))
                matchedUUIDs.insert(mod.uuid)
                continue
            }

            // Try fuzzy name match (contains, ignoring case)
            if !id.isEmpty {
                let lowered = id.lowercased()
                if let mod = mods.first(where: {
                    !matchedUUIDs.contains($0.uuid) && (
                        $0.name.lowercased().contains(lowered) ||
                        lowered.contains($0.name.lowercased())
                    )
                }) {
                    matched.append(MatchedEntry(
                        parsedEntry: entry, matchedMod: mod, matchType: .fuzzyName
                    ))
                    matchedUUIDs.insert(mod.uuid)
                    continue
                }
            }

            unmatched.append(entry)
        }

        return ImportResult(
            format: format,
            totalParsed: entries.count,
            matched: matched,
            unmatched: unmatched
        )
    }

    // MARK: - Helpers

    func isNexusURL(_ string: String) -> Bool {
        guard let components = URLComponents(string: string),
              let host = components.host?.lowercased() else { return false }
        return host == "nexusmods.com" || host.hasSuffix(".nexusmods.com")
    }

    /// Extract mod ID from a Nexus URL like
    /// "https://www.nexusmods.com/baldursgate3/mods/12345"
    func extractModID(from url: String) -> String? {
        let pattern = #"/mods/(\d+)"#
        guard let range = url.range(of: pattern, options: .regularExpression) else {
            return nil
        }
        let matched = url[range]
        guard let numRange = matched.range(of: #"\d+"#, options: .regularExpression) else {
            return nil
        }
        return String(url[numRange])
    }

    private func looksLikeHeader(_ line: String, separator: Character) -> Bool {
        let knownHeaderNames: Set<String> = [
            "name", "mod", "mod_name", "mod name", "modname", "title",
            "url", "nexus_url", "nexusurl", "nexus url", "nexus_link", "link",
            "uuid", "id", "identifier", "mod_id",
        ]
        let fields = line.split(separator: separator, omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
        return fields.contains { knownHeaderNames.contains($0) }
    }
}
