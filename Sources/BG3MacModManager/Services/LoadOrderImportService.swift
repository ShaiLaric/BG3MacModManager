import Foundation

/// Parses external load order formats (BG3MM JSON, standalone modsettings.lsx)
/// and produces a normalized list of mod entries for import.
final class LoadOrderImportService {

    enum ImportFormat {
        case bg3mm      // JSON from BG3 Mod Manager (Windows)
        case lsx        // Raw modsettings.lsx file
    }

    enum ImportError: Error, LocalizedError {
        case invalidJSON(String)
        case unknownFormat(String)
        case emptyModList

        var errorDescription: String? {
            switch self {
            case .invalidJSON(let msg): return "Invalid BG3MM JSON: \(msg)"
            case .unknownFormat(let ext): return "Unrecognized load order format: .\(ext)"
            case .emptyModList: return "The imported file contains no mods"
            }
        }
    }

    /// A single entry from an imported load order (format-agnostic).
    struct ImportedModEntry {
        let uuid: String
        let name: String
        let folder: String
        let version64: Int64
        let md5: String
    }

    /// Result of parsing an external load order file.
    struct ImportResult {
        let format: ImportFormat
        let entries: [ImportedModEntry]
        let sourceName: String
    }

    private let modSettingsService = ModSettingsService()

    // MARK: - Public API

    /// Detect format and parse a file URL into an ImportResult.
    func parseFile(at url: URL) throws -> ImportResult {
        let ext = url.pathExtension.lowercased()
        if ext == "json" {
            return try parseBG3MMJSON(at: url)
        } else if ext == "lsx" {
            return try parseLSX(at: url)
        }
        throw ImportError.unknownFormat(ext)
    }

    // MARK: - BG3MM JSON Parsing

    private func parseBG3MMJSON(at url: URL) throws -> ImportResult {
        let data = try Data(contentsOf: url)

        let export: BG3MMExport
        do {
            export = try JSONDecoder().decode(BG3MMExport.self, from: data)
        } catch {
            throw ImportError.invalidJSON(error.localizedDescription)
        }

        let entries = export.mods
            .filter { !Constants.builtInModuleUUIDs.contains($0.UUID.lowercased()) }
            .map { mod in
                ImportedModEntry(
                    uuid: mod.UUID.lowercased(),
                    name: mod.modName,
                    folder: mod.folder,
                    version64: Int64(mod.version) ?? 36028797018963968,
                    md5: mod.md5
                )
            }

        guard !entries.isEmpty else { throw ImportError.emptyModList }

        return ImportResult(
            format: .bg3mm,
            entries: entries,
            sourceName: "BG3 Mod Manager"
        )
    }

    // MARK: - LSX Parsing

    private func parseLSX(at url: URL) throws -> ImportResult {
        let settings = try modSettingsService.read(from: url)

        let entries: [ImportedModEntry] = settings.modOrder.compactMap { uuid in
            guard !Constants.builtInModuleUUIDs.contains(uuid.lowercased()) else { return nil }
            let desc = settings.mods[uuid]
            return ImportedModEntry(
                uuid: uuid.lowercased(),
                name: desc?.name ?? uuid,
                folder: desc?.folder ?? "",
                version64: Int64(desc?.version64 ?? "") ?? 36028797018963968,
                md5: desc?.md5 ?? ""
            )
        }

        guard !entries.isEmpty else { throw ImportError.emptyModList }

        return ImportResult(
            format: .lsx,
            entries: entries,
            sourceName: "modsettings.lsx"
        )
    }
}

// MARK: - BG3MM JSON Model

private struct BG3MMExport: Codable {
    let mods: [BG3MMMod]
}

private struct BG3MMMod: Codable {
    let modName: String
    let UUID: String
    let folder: String
    let version: String
    let md5: String
}
