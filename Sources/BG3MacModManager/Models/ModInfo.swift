// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import CryptoKit

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

    /// Declared conflicts (UUIDs of incompatible mods, from meta.lsx <Conflicts> node).
    var conflicts: [ModDependency]

    /// Whether this mod requires bg3se-macos (Script Extender).
    var requiresScriptExtender: Bool

    /// The `.pak` filename on disk (e.g., "MyMod.pak").
    var pakFileName: String?

    /// Full path to the `.pak` file.
    var pakFilePath: URL?

    /// Source of the metadata (how it was discovered).
    var metadataSource: MetadataSource

    /// Inferred or user-assigned load order category for smart sorting.
    var category: ModCategory? = nil

    // MARK: - Identifiable

    var id: String { uuid }

    // MARK: - Computed Properties

    var version: Version64 {
        Version64(rawValue: version64)
    }

    var isBasicGameModule: Bool {
        uuid == Constants.baseModuleUUID || uuid == Constants.gustavDevUUID
    }

    // MARK: - Factory Methods

    /// Creates a ModInfo for the required base game module (GustavX / GustavDev).
    static var baseGameModule: ModInfo {
        ModInfo(
            uuid: Constants.baseModuleUUID,
            folder: Constants.baseModuleFolder,
            name: Constants.baseModuleName,
            author: "Larian Studios",
            modDescription: "Base game module (required)",
            version64: Constants.baseModuleVersion64,
            md5: "",
            tags: [],
            dependencies: [],
            conflicts: [],
            requiresScriptExtender: false,
            pakFileName: nil,
            pakFilePath: nil,
            metadataSource: .builtIn
        )
    }

    /// Creates a minimal ModInfo from just a pak filename when no metadata is available.
    /// Uses a deterministic UUID derived from the filename so refreshes produce stable identifiers.
    static func fromPakFilename(_ filename: String, at url: URL) -> ModInfo {
        let name = filename.replacingOccurrences(of: ".pak", with: "")
        let deterministicUUID = Self.deterministicUUID(from: filename)
        return ModInfo(
            uuid: deterministicUUID,
            folder: name,
            name: name,
            author: "Unknown",
            modDescription: "",
            version64: Version64(major: 1).rawValue,
            md5: "",
            tags: [],
            dependencies: [],
            conflicts: [],
            requiresScriptExtender: false,
            pakFileName: filename,
            pakFilePath: url,
            metadataSource: .filename
        )
    }

    /// Generate a deterministic UUID from a string using SHA-256.
    /// This ensures the same filename always produces the same UUID across refreshes.
    private static func deterministicUUID(from input: String) -> String {
        let digest = SHA256.hash(data: Data(input.lowercased().utf8))
        var bytes = Array(digest.prefix(16))
        // Set version nibble (byte 6, high nibble) to 5 (UUID v5-style)
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        // Set variant bits (byte 8, high 2 bits) to 10 (RFC 4122)
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return String(
            format: "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
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

    /// Higher values = more trusted/complete metadata.
    var priority: Int {
        switch self {
        case .builtIn:      return 5
        case .metaLsx:      return 4
        case .infoJson:     return 3
        case .modSettings:  return 2
        case .filename:     return 1
        }
    }
}

// MARK: - Constants

enum Constants {
    /// GustavX - the base game module (renamed from GustavDev in Patch 7+).
    static let baseModuleUUID = "cb555efe-2d9e-131f-8195-a89329d218ea"
    static let baseModuleFolder = "GustavX"
    static let baseModuleName = "GustavX"
    static let baseModuleVersion64: Int64 = 36028797018963968 // 1.0.0.0

    /// Legacy GustavDev UUID (pre-Patch 7).
    static let gustavDevUUID = "28ac9ce2-2aba-8cda-b3b5-6e922f71b6b8"

    /// All built-in game module UUIDs that should never be flagged as missing dependencies.
    /// Sourced from LaughingLeader/BG3ModManager IgnoredMods.json.
    static let builtInModuleUUIDs: Set<String> = [
        "991c9c7a-fb80-40cb-8f0d-b92d4e80e9b1", // Gustav
        "28ac9ce2-2aba-8cda-b3b5-6e922f71b6b8", // GustavDev
        "cb555efe-2d9e-131f-8195-a89329d218ea", // GustavX
        "ed539163-bb70-431b-96a7-f5b2eda5376b", // Shared
        "3d0c5ff8-c95d-c907-ff3e-34b204f1c630", // SharedDev
        "9dff4c3b-fda7-43de-a763-ce1383039999", // Engine
        "e842840a-2449-588c-b0c4-22122cfce31b", // DiceSet_01
        "b176a0ac-d79f-ed9d-5a87-5c2c80874e10", // DiceSet_02
        "e0a4d990-7b9b-8fa9-d7c6-04017c6cf5b1", // DiceSet_03
        "77a2155f-4b35-4f0c-e7ff-4338f91426a4", // DiceSet_04
        "6efc8f44-cc2a-0273-d4b1-681d3faa411b", // DiceSet_05
        "ee4989eb-aab8-968f-8674-812ea2f4bfd7", // DiceSet_06
        "bf19bab4-4908-ef39-9065-ced469c0f877", // DiceSet_07
        "b77b6210-ac50-4cb1-a3d5-5702fb9c744c", // Honour
        "767d0062-d82c-279c-e16b-dfee7fe94cdd", // HonourX
        "ee5a55ff-eb38-0b27-c5b0-f358dc306d34", // ModBrowser
        "630daa32-70f8-3da5-41b9-154fe8410236", // MainUI
        "e1ce736b-52e6-e713-e9e7-e6abbb15a198", // CrossplayUI
        "55ef175c-59e3-b44b-3fb2-8f86acc5d550", // PhotoMode
    ]

    /// Steam App ID for BG3.
    static let steamAppID = "1086940"
}
