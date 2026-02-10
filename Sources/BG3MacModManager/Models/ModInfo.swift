import Foundation

/// Represents a single BG3 mod with all known metadata.
struct ModInfo: Identifiable, Codable, Equatable {
    /// Unique identifier for this mod (from meta.lsx / info.json UUID field).
    let uuid: String

    /// The folder name inside the `.pak` archive (e.g., "MyModFolder").
    var folder: String

    /// Display name of the mod.
    var name: String

    /// Author of the mod.
    var author: String

    /// Description text.
    var modDescription: String

    /// Version in BG3's Int64 format.
    var version64: Int64

    /// MD5 hash (often empty in practice).
    var md5: String

    /// Tags (semicolon-separated in meta.lsx).
    var tags: [String]

    /// Dependencies (UUIDs of required mods).
    var dependencies: [ModDependency]

    /// Whether this mod requires bg3se-macos (Script Extender).
    var requiresScriptExtender: Bool

    /// The `.pak` filename on disk (e.g., "MyMod.pak").
    var pakFileName: String?

    /// Full path to the `.pak` file.
    var pakFilePath: URL?

    /// Source of the metadata (how it was discovered).
    var metadataSource: MetadataSource

    // MARK: - Identifiable

    var id: String { uuid }

    // MARK: - Computed Properties

    var version: Version64 {
        Version64(rawValue: version64)
    }

    var isBasicGameModule: Bool {
        uuid == Constants.gustavDevUUID
    }

    // MARK: - Factory Methods

    /// Creates a ModInfo for the required GustavDev base game module.
    static var gustavDev: ModInfo {
        ModInfo(
            uuid: Constants.gustavDevUUID,
            folder: "GustavDev",
            name: "GustavDev",
            author: "Larian Studios",
            modDescription: "Base game module (required)",
            version64: Constants.gustavDevVersion64,
            md5: "",
            tags: [],
            dependencies: [],
            requiresScriptExtender: false,
            pakFileName: nil,
            pakFilePath: nil,
            metadataSource: .builtIn
        )
    }

    /// Creates a minimal ModInfo from just a pak filename when no metadata is available.
    static func fromPakFilename(_ filename: String, at url: URL) -> ModInfo {
        let name = filename.replacingOccurrences(of: ".pak", with: "")
        return ModInfo(
            uuid: UUID().uuidString.lowercased(),
            folder: name,
            name: name,
            author: "Unknown",
            modDescription: "",
            version64: Version64(major: 1).rawValue,
            md5: "",
            tags: [],
            dependencies: [],
            requiresScriptExtender: false,
            pakFileName: filename,
            pakFilePath: url,
            metadataSource: .filename
        )
    }
}

// MARK: - Supporting Types

struct ModDependency: Codable, Equatable, Identifiable {
    let uuid: String
    var folder: String
    var name: String
    var version64: Int64
    var md5: String

    var id: String { uuid }
}

/// Indicates how mod metadata was obtained.
enum MetadataSource: String, Codable {
    case infoJson     // Parsed from info.json alongside the .pak
    case metaLsx      // Extracted from meta.lsx inside the .pak
    case filename     // Fallback: derived from the .pak filename
    case builtIn      // Hard-coded (e.g., GustavDev)
    case modSettings  // Imported from modsettings.lsx
}

// MARK: - Constants

enum Constants {
    static let gustavDevUUID = "28ac9ce2-2aba-8cda-b3b5-6e922f71b6b8"
    static let gustavDevVersion64: Int64 = 145_100_779_997_082_624 // 36028797018963968 in some versions

    /// Steam App ID for BG3.
    static let steamAppID = "1086940"
}
