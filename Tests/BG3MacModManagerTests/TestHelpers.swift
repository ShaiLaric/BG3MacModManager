// SPDX-License-Identifier: GPL-3.0-or-later

import Compression
import Foundation
import LZ4
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

/// Creates a minimal, uncompressed LSF v7 `meta.lsf` containing save module settings.
func makeTestSaveMetadataLSF(
    gameID: String,
    mods: [SaveModEntry],
    order: [String],
    compressSections: Bool = false
) throws -> Data {
    let nodeNames = ["Meta", "ModuleSettings", "Mods", "ModuleShortDesc", "ModOrder", "Module"]
    let attributeNames = ["GameID", "UUID", "Folder", "Name", "Version64", "MD5"]
    let names = nodeNames + attributeNames
    let nameReferences = Dictionary(uniqueKeysWithValues: names.enumerated().map {
        ($0.element, UInt32($0.offset) << 16)
    })

    var namesData = Data()
    namesData.append(testLittleEndianBytes(UInt32(names.count)))
    for name in names {
        namesData.append(testLittleEndianBytes(UInt16(1)))
        namesData.append(testLittleEndianBytes(UInt16(name.utf8.count)))
        namesData.append(Data(name.utf8))
    }

    struct TestNode {
        let name: String
        let firstAttribute: Int32
        let parent: Int32
    }
    var nodes: [TestNode] = [
        .init(name: "Meta", firstAttribute: 0, parent: -1),
        .init(name: "ModuleSettings", firstAttribute: -1, parent: 0),
        .init(name: "Mods", firstAttribute: -1, parent: 1),
    ]

    var attributes: [(name: String, type: UInt32, data: Data, node: Int32)] = []
    func stringData(_ value: String) -> Data {
        var data = Data(value.utf8)
        data.append(0)
        return data
    }
    attributes.append(("GameID", 22, stringData(gameID), 0))

    for mod in mods {
        let nodeIndex = Int32(nodes.count)
        let firstAttribute = Int32(attributes.count)
        nodes.append(.init(name: "ModuleShortDesc", firstAttribute: firstAttribute, parent: 2))
        attributes.append(("UUID", 22, stringData(mod.uuid), nodeIndex))
        attributes.append(("Folder", 22, stringData(mod.folder), nodeIndex))
        attributes.append(("Name", 22, stringData(mod.name), nodeIndex))
        attributes.append(("Version64", 24, testLittleEndianBytes(UInt64(bitPattern: mod.version64)), nodeIndex))
        attributes.append(("MD5", 22, stringData(mod.md5), nodeIndex))
    }

    let modOrderNodeIndex = Int32(nodes.count)
    nodes.append(.init(name: "ModOrder", firstAttribute: -1, parent: 1))
    for uuid in order {
        let nodeIndex = Int32(nodes.count)
        nodes.append(.init(
            name: "Module",
            firstAttribute: Int32(attributes.count),
            parent: modOrderNodeIndex
        ))
        attributes.append(("UUID", 22, stringData(uuid), nodeIndex))
    }

    var nodesData = Data()
    for node in nodes {
        nodesData.append(testLittleEndianBytes(nameReferences[node.name]!))
        nodesData.append(testLittleEndianBytes(node.firstAttribute))
        nodesData.append(testLittleEndianBytes(node.parent))
    }

    var attributesData = Data()
    var valuesData = Data()
    for attribute in attributes {
        attributesData.append(testLittleEndianBytes(nameReferences[attribute.name]!))
        let typeAndLength = (UInt32(attribute.data.count) << 6) | attribute.type
        attributesData.append(testLittleEndianBytes(typeAndLength))
        attributesData.append(testLittleEndianBytes(attribute.node))
        valuesData.append(attribute.data)
    }

    let storedNames: Data
    let storedNodes: Data
    let storedAttributes: Data
    let storedValues: Data
    if compressSections {
        storedNames = try testCompressRawLZ4(namesData)
        storedNodes = try LZ4.memory.compress(data: nodesData)
        storedAttributes = try LZ4.memory.compress(data: attributesData)
        storedValues = try LZ4.memory.compress(data: valuesData)
    } else {
        storedNames = namesData
        storedNodes = nodesData
        storedAttributes = attributesData
        storedValues = valuesData
    }

    var result = Data("LSOF".utf8)
    result.append(testLittleEndianBytes(UInt32(7)))
    result.append(testLittleEndianBytes(UInt64(0)))
    result.append(testLittleEndianBytes(UInt32(namesData.count)))
    result.append(testLittleEndianBytes(UInt32(compressSections ? storedNames.count : 0)))
    result.append(testLittleEndianBytes(UInt32(0))) // Keys expanded
    result.append(testLittleEndianBytes(UInt32(0))) // Keys stored
    result.append(testLittleEndianBytes(UInt32(nodesData.count)))
    result.append(testLittleEndianBytes(UInt32(compressSections ? storedNodes.count : 0)))
    result.append(testLittleEndianBytes(UInt32(attributesData.count)))
    result.append(testLittleEndianBytes(UInt32(compressSections ? storedAttributes.count : 0)))
    result.append(testLittleEndianBytes(UInt32(valuesData.count)))
    result.append(testLittleEndianBytes(UInt32(compressSections ? storedValues.count : 0)))
    result.append(contentsOf: [compressSections ? 0x22 : 0, 0])
    result.append(testLittleEndianBytes(UInt16(0)))
    result.append(testLittleEndianBytes(UInt32(0))) // V2 metadata layout
    result.append(storedNames)
    result.append(storedNodes)
    result.append(storedAttributes)
    result.append(storedValues)
    return result
}

private func testCompressRawLZ4(_ data: Data) throws -> Data {
    let capacity = data.count * 2 + 1_024
    var output = Data(count: capacity)
    let encoded = output.withUnsafeMutableBytes { destination in
        data.withUnsafeBytes { source in
            guard let destinationAddress = destination.baseAddress?.assumingMemoryBound(to: UInt8.self),
                  let sourceAddress = source.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_encode_buffer(
                destinationAddress,
                capacity,
                sourceAddress,
                data.count,
                nil,
                COMPRESSION_LZ4_RAW
            )
        }
    }
    guard encoded > 0 else {
        throw NSError(domain: "TestLSF", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Could not encode raw LZ4 test data",
        ])
    }
    output.count = encoded
    return output
}
