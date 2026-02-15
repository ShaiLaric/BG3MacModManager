// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
@testable import BG3MacModManager

/// Creates a ModInfo with sensible defaults. Override any field as needed.
func makeModInfo(
    uuid: String = UUID().uuidString.lowercased(),
    folder: String = "TestMod",
    name: String = "Test Mod",
    author: String = "Test Author",
    modDescription: String = "",
    version64: Int64 = 36028797018963968, // 1.0.0.0
    md5: String = "",
    tags: [String] = [],
    dependencies: [ModDependency] = [],
    conflicts: [ModDependency] = [],
    requiresScriptExtender: Bool = false,
    pakFileName: String? = "TestMod.pak",
    pakFilePath: URL? = nil,
    metadataSource: MetadataSource = .metaLsx,
    category: ModCategory? = nil
) -> ModInfo {
    ModInfo(
        uuid: uuid,
        folder: folder,
        name: name,
        author: author,
        modDescription: modDescription,
        version64: version64,
        md5: md5,
        tags: tags,
        dependencies: dependencies,
        conflicts: conflicts,
        requiresScriptExtender: requiresScriptExtender,
        pakFileName: pakFileName,
        pakFilePath: pakFilePath,
        metadataSource: metadataSource,
        category: category
    )
}

/// Creates a ModDependency with sensible defaults.
func makeDependency(
    uuid: String = UUID().uuidString.lowercased(),
    folder: String = "DepFolder",
    name: String = "Dependency",
    version64: Int64 = 36028797018963968,
    md5: String = ""
) -> ModDependency {
    ModDependency(
        uuid: uuid,
        folder: folder,
        name: name,
        version64: version64,
        md5: md5
    )
}

/// Creates a ScriptExtenderService.SEStatus with sensible defaults.
func makeSEStatus(
    isInstalled: Bool = false,
    isDeployed: Bool = false,
    dylibPath: URL? = nil,
    logsAvailable: Bool = false,
    latestLogPath: URL? = nil
) -> ScriptExtenderService.SEStatus {
    ScriptExtenderService.SEStatus(
        isInstalled: isInstalled,
        isDeployed: isDeployed,
        dylibPath: dylibPath,
        logsAvailable: logsAvailable,
        latestLogPath: latestLogPath
    )
}
