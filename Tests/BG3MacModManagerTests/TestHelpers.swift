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

/// Creates a minimal valid v18 PAK containing raw, uncompressed entries.
func makeUncompressedTestPak(entries: [(name: String, contents: Data)]) -> Data {
    let headerByteCount = 40
    let entryByteCount = 272
    let contentsByteCount = entries.reduce(0) { $0 + $1.contents.count }
    let fileListOffset = UInt64(headerByteCount + contentsByteCount)
    let fileListSize = UInt32(8 + entryByteCount * entries.count)

    var pak = Data([0x4C, 0x53, 0x50, 0x4B])
    pak.append(testLittleEndianBytes(UInt32(18)))
    pak.append(testLittleEndianBytes(fileListOffset))
    pak.append(testLittleEndianBytes(fileListSize))
    pak.append(contentsOf: [0, 0])
    pak.append(Data(count: 16))
    pak.append(testLittleEndianBytes(UInt16(1)))

    var offsets: [UInt32] = []
    var nextOffset = UInt32(headerByteCount)
    for entry in entries {
        offsets.append(nextOffset)
        pak.append(entry.contents)
        nextOffset += UInt32(entry.contents.count)
    }

    pak.append(testLittleEndianBytes(UInt32(entries.count)))
    pak.append(testLittleEndianBytes(UInt32(entryByteCount * entries.count)))
    for (index, entryValue) in entries.enumerated() {
        var entry = Data(entryValue.name.utf8)
        precondition(entry.count <= 256)
        entry.append(Data(count: 256 - entry.count))
        entry.append(testLittleEndianBytes(offsets[index]))
        entry.append(testLittleEndianBytes(UInt16(0)))
        entry.append(contentsOf: [0, 0])
        entry.append(testLittleEndianBytes(UInt32(entryValue.contents.count)))
        entry.append(testLittleEndianBytes(UInt32(entryValue.contents.count)))
        precondition(entry.count == entryByteCount)
        pak.append(entry)
    }

    return pak
}

private func testLittleEndianBytes<T: FixedWidthInteger>(_ value: T) -> Data {
    var value = value.littleEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
