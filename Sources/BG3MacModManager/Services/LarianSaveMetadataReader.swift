// SPDX-License-Identifier: GPL-3.0-or-later

import Compression
import Foundation
import LZ4
import ZSTD

/// Reads the small `ModuleSettings` subset of BG3's binary `meta.lsf` save metadata.
/// The on-disk structures follow Larian's LSF v1-v7 layout; unrelated gameplay data
/// and attribute types are intentionally ignored.
struct LarianSaveMetadataReader: Sendable {
    struct Result: Equatable, Sendable {
        let gameID: String?
        let mods: [SaveModEntry]
    }

    enum ReaderError: Error, LocalizedError {
        case invalidSignature
        case unsupportedVersion(UInt32)
        case unsupportedCompression(UInt8)
        case malformed(String)
        case limitExceeded(String)
        case decompressionFailed

        var errorDescription: String? {
            switch self {
            case .invalidSignature: return "The save metadata has an invalid LSF signature."
            case .unsupportedVersion(let version): return "LSF version \(version) is not supported."
            case .unsupportedCompression(let method):
                return "LSF compression method \(method) is not supported."
            case .malformed(let detail): return "The save metadata is malformed: \(detail)."
            case .limitExceeded(let detail): return "The save metadata exceeds the safety limit for \(detail)."
            case .decompressionFailed: return "The save metadata could not be decompressed."
            }
        }
    }

    struct Limits: Sendable {
        let maximumSectionBytes: Int
        let maximumTotalExpandedBytes: Int
        let maximumNames: Int
        let maximumNodes: Int
        let maximumAttributes: Int

        static let `default` = Limits(
            maximumSectionBytes: 32 * 1_024 * 1_024,
            maximumTotalExpandedBytes: 96 * 1_024 * 1_024,
            maximumNames: 100_000,
            maximumNodes: 1_000_000,
            maximumAttributes: 4_000_000
        )
    }

    private struct SectionSizes {
        let expanded: Int
        let stored: Int
    }

    private struct Node {
        let name: String
        let parentIndex: Int
        let firstAttributeIndex: Int
    }

    private struct Attribute {
        let name: String
        let type: UInt32
        let length: Int
        let dataOffset: Int
        var nextAttributeIndex: Int
    }

    private enum Value: Equatable {
        case string(String)
        case unsigned(UInt64)
        case signed(Int64)
        case boolean(Bool)

        var text: String? {
            switch self {
            case .string(let value): return value
            case .unsigned(let value): return String(value)
            case .signed(let value): return String(value)
            case .boolean(let value): return value ? "true" : "false"
            }
        }
    }

    func read(data: Data, limits: Limits = .default) throws -> Result {
        var cursor = BinaryCursor(data: data)
        guard try cursor.readData(count: 4) == Data("LSOF".utf8) else {
            throw ReaderError.invalidSignature
        }
        let version = try cursor.readUInt32()
        guard (1...7).contains(version) else { throw ReaderError.unsupportedVersion(version) }
        _ = try cursor.readData(count: version >= 5 ? 8 : 4) // Engine version

        let strings = SectionSizes(
            expanded: try checkedSize(cursor.readUInt32(), name: "name table", limits: limits),
            stored: try checkedSize(cursor.readUInt32(), name: "stored name table", limits: limits)
        )

        let keys: SectionSizes
        if version >= 6 {
            keys = SectionSizes(
                expanded: try checkedSize(cursor.readUInt32(), name: "key table", limits: limits),
                stored: try checkedSize(cursor.readUInt32(), name: "stored key table", limits: limits)
            )
        } else {
            keys = SectionSizes(expanded: 0, stored: 0)
        }

        let nodes = SectionSizes(
            expanded: try checkedSize(cursor.readUInt32(), name: "node table", limits: limits),
            stored: try checkedSize(cursor.readUInt32(), name: "stored node table", limits: limits)
        )
        let attributes = SectionSizes(
            expanded: try checkedSize(cursor.readUInt32(), name: "attribute table", limits: limits),
            stored: try checkedSize(cursor.readUInt32(), name: "stored attribute table", limits: limits)
        )
        let values = SectionSizes(
            expanded: try checkedSize(cursor.readUInt32(), name: "value table", limits: limits),
            stored: try checkedSize(cursor.readUInt32(), name: "stored value table", limits: limits)
        )
        let compressionFlags = try cursor.readUInt8()
        _ = try cursor.readUInt8()
        _ = try cursor.readUInt16()
        let metadataFormat = try cursor.readUInt32()
        guard metadataFormat <= 2 else {
            throw ReaderError.malformed("unknown metadata format \(metadataFormat)")
        }

        let expandedTotal = [strings, keys, nodes, attributes, values].reduce(0) { partial, section in
            partial.addingReportingOverflow(section.expanded).overflow
                ? Int.max
                : partial + section.expanded
        }
        guard expandedTotal <= limits.maximumTotalExpandedBytes else {
            throw ReaderError.limitExceeded("expanded data")
        }

        let namesData = try readSection(
            from: &cursor,
            sizes: strings,
            compressionFlags: compressionFlags,
            framedLZ4: false
        )
        let nodesData = try readSection(
            from: &cursor,
            sizes: nodes,
            compressionFlags: compressionFlags,
            framedLZ4: version >= 2
        )
        let attributesData = try readSection(
            from: &cursor,
            sizes: attributes,
            compressionFlags: compressionFlags,
            framedLZ4: version >= 2
        )
        let valuesData = try readSection(
            from: &cursor,
            sizes: values,
            compressionFlags: compressionFlags,
            framedLZ4: version >= 2
        )
        // Key names are serialized last. They are not needed to recover module settings,
        // but consuming and validating the section catches truncated metadata.
        _ = try readSection(
            from: &cursor,
            sizes: keys,
            compressionFlags: compressionFlags,
            framedLZ4: version >= 2
        )

        let names = try parseNames(namesData, limits: limits)
        let usesAdjacency = version >= 3 && metadataFormat == 1
        let parsedNodes = try parseNodes(
            nodesData,
            names: names,
            usesAdjacency: usesAdjacency,
            limits: limits
        )
        let parsedAttributes = try parseAttributes(
            attributesData,
            names: names,
            usesAdjacency: usesAdjacency,
            limits: limits
        )

        return try extractResult(
            nodes: parsedNodes,
            attributes: parsedAttributes,
            values: valuesData
        )
    }

    private func checkedSize(_ value: UInt32, name: String, limits: Limits) throws -> Int {
        let result = Int(value)
        guard result <= limits.maximumSectionBytes else {
            throw ReaderError.limitExceeded(name)
        }
        return result
    }

    private func readSection(
        from cursor: inout BinaryCursor,
        sizes: SectionSizes,
        compressionFlags: UInt8,
        framedLZ4: Bool
    ) throws -> Data {
        guard sizes.expanded > 0 else {
            guard sizes.stored == 0 else { throw ReaderError.malformed("empty section has stored bytes") }
            return Data()
        }

        if sizes.stored == 0 {
            return try cursor.readData(count: sizes.expanded)
        }

        let method = compressionFlags & 0x0f
        let storedByteCount = method == 0 ? sizes.expanded : sizes.stored
        let stored = try cursor.readData(count: storedByteCount)
        switch method {
        case 0:
            guard stored.count == sizes.expanded else { throw ReaderError.decompressionFailed }
            return stored
        case 1:
            return try decompressApple(stored, expectedSize: sizes.expanded, algorithm: COMPRESSION_ZLIB)
        case 2:
            if framedLZ4 {
                return try decompressLZ4Frame(stored, expectedSize: sizes.expanded)
            }
            return try decompressApple(stored, expectedSize: sizes.expanded, algorithm: COMPRESSION_LZ4_RAW)
        case 3:
            return try decompressZstandard(stored, expectedSize: sizes.expanded)
        default:
            throw ReaderError.unsupportedCompression(method)
        }
    }

    private func parseNames(_ data: Data, limits: Limits) throws -> [[String]] {
        var cursor = BinaryCursor(data: data)
        let bucketCount = Int(try cursor.readUInt32())
        guard bucketCount <= limits.maximumNames else { throw ReaderError.limitExceeded("name buckets") }
        var result: [[String]] = []
        result.reserveCapacity(bucketCount)
        var totalNames = 0
        for _ in 0..<bucketCount {
            let chainLength = Int(try cursor.readUInt16())
            totalNames += chainLength
            guard totalNames <= limits.maximumNames else { throw ReaderError.limitExceeded("names") }
            var bucket: [String] = []
            bucket.reserveCapacity(chainLength)
            for _ in 0..<chainLength {
                let length = Int(try cursor.readUInt16())
                let bytes = try cursor.readData(count: length)
                guard let name = String(data: bytes, encoding: .utf8) else {
                    throw ReaderError.malformed("invalid UTF-8 in name table")
                }
                bucket.append(name)
            }
            result.append(bucket)
        }
        guard cursor.isAtEnd else { throw ReaderError.malformed("trailing name-table data") }
        return result
    }

    private func parseNodes(
        _ data: Data,
        names: [[String]],
        usesAdjacency: Bool,
        limits: Limits
    ) throws -> [Node] {
        let entrySize = usesAdjacency ? 16 : 12
        guard data.count.isMultiple(of: entrySize) else { throw ReaderError.malformed("partial node entry") }
        let count = data.count / entrySize
        guard count <= limits.maximumNodes else { throw ReaderError.limitExceeded("nodes") }
        var cursor = BinaryCursor(data: data)
        var result: [Node] = []
        result.reserveCapacity(count)
        for index in 0..<count {
            let nameReference = try cursor.readUInt32()
            let parentIndex: Int
            let firstAttributeIndex: Int
            if usesAdjacency {
                parentIndex = try cursor.readInt32()
                _ = try cursor.readInt32() // Next sibling
                firstAttributeIndex = try cursor.readInt32()
            } else {
                firstAttributeIndex = try cursor.readInt32()
                parentIndex = try cursor.readInt32()
            }
            guard parentIndex < index, parentIndex >= -1 else {
                throw ReaderError.malformed("invalid parent index")
            }
            result.append(Node(
                name: try resolveName(nameReference, names: names),
                parentIndex: parentIndex,
                firstAttributeIndex: firstAttributeIndex
            ))
        }
        return result
    }

    private func parseAttributes(
        _ data: Data,
        names: [[String]],
        usesAdjacency: Bool,
        limits: Limits
    ) throws -> [Attribute] {
        let entrySize = usesAdjacency ? 16 : 12
        guard data.count.isMultiple(of: entrySize) else { throw ReaderError.malformed("partial attribute entry") }
        let count = data.count / entrySize
        guard count <= limits.maximumAttributes else { throw ReaderError.limitExceeded("attributes") }
        var cursor = BinaryCursor(data: data)
        var result: [Attribute] = []
        result.reserveCapacity(count)
        var runningValueOffset = 0
        var previousByNodeReference: [Int] = []

        for index in 0..<count {
            let nameReference = try cursor.readUInt32()
            let typeAndLength = try cursor.readUInt32()
            let type = typeAndLength & 0x3f
            let length = Int(typeAndLength >> 6)
            let third = try cursor.readInt32()
            let offset: Int
            let next: Int
            if usesAdjacency {
                next = third
                offset = Int(try cursor.readUInt32())
            } else {
                next = -1
                offset = runningValueOffset
                let (newOffset, overflow) = runningValueOffset.addingReportingOverflow(length)
                guard !overflow else { throw ReaderError.malformed("attribute value offsets overflow") }
                runningValueOffset = newOffset
            }
            result.append(Attribute(
                name: try resolveName(nameReference, names: names),
                type: type,
                length: length,
                dataOffset: offset,
                nextAttributeIndex: next
            ))

            guard !usesAdjacency else { continue }
            let nodeReference = Int(third) + 1
            guard nodeReference >= 0 else { throw ReaderError.malformed("invalid attribute node reference") }
            while previousByNodeReference.count <= nodeReference { previousByNodeReference.append(-1) }
            if previousByNodeReference[nodeReference] >= 0 {
                result[previousByNodeReference[nodeReference]].nextAttributeIndex = index
            }
            previousByNodeReference[nodeReference] = index
        }
        return result
    }

    private func extractResult(
        nodes: [Node],
        attributes: [Attribute],
        values: Data
    ) throws -> Result {
        var attributesByNode: [[String: Value]] = []
        attributesByNode.reserveCapacity(nodes.count)
        for node in nodes {
            var nodeAttributes: [String: Value] = [:]
            var attributeIndex = node.firstAttributeIndex
            var visited = Set<Int>()
            while attributeIndex != -1 {
                guard attributes.indices.contains(attributeIndex), visited.insert(attributeIndex).inserted else {
                    throw ReaderError.malformed("invalid attribute chain")
                }
                let attribute = attributes[attributeIndex]
                if let value = try parseValue(attribute, from: values) {
                    nodeAttributes[attribute.name] = value
                }
                attributeIndex = attribute.nextAttributeIndex
            }
            attributesByNode.append(nodeAttributes)
        }

        let descriptorIndices = nodes.indices.filter {
            nodes[$0].name == "ModuleShortDesc" && hasAncestor(named: "Mods", from: $0, nodes: nodes)
        }
        var descriptors: [String: SaveModEntry] = [:]
        var descriptorOrder: [String] = []
        for index in descriptorIndices {
            let attributes = attributesByNode[index]
            guard let rawUUID = attributes["UUID"]?.text,
                  let uuid = ModIdentity.normalizedUUID(rawUUID) else { continue }
            let entry = SaveModEntry(
                uuid: uuid,
                name: attributes["Name"]?.text ?? uuid,
                folder: attributes["Folder"]?.text ?? "",
                version64: Int64(attributes["Version64"]?.text ?? "") ?? 0,
                md5: attributes["MD5"]?.text ?? ""
            )
            descriptors[uuid] = entry
            descriptorOrder.append(uuid)
        }

        let explicitOrder = nodes.indices.compactMap { index -> String? in
            guard nodes[index].name == "Module",
                  hasAncestor(named: "ModOrder", from: index, nodes: nodes),
                  let rawUUID = attributesByNode[index]["UUID"]?.text else { return nil }
            return ModIdentity.normalizedUUID(rawUUID)
        }
        let orderedUUIDs = explicitOrder.isEmpty ? descriptorOrder : explicitOrder
        var seenUUIDs = Set<String>()
        let mods = orderedUUIDs.compactMap { uuid -> SaveModEntry? in
            guard seenUUIDs.insert(uuid).inserted else { return nil }
            return descriptors[uuid] ?? SaveModEntry(
                uuid: uuid,
                name: uuid,
                folder: "",
                version64: 0,
                md5: ""
            )
        }
        let gameID = attributesByNode.lazy.compactMap { $0["GameID"]?.text }.first
        return Result(gameID: gameID, mods: mods)
    }

    private func hasAncestor(named name: String, from index: Int, nodes: [Node]) -> Bool {
        var parent = nodes[index].parentIndex
        var remaining = nodes.count
        while parent >= 0, remaining > 0 {
            guard nodes.indices.contains(parent) else { return false }
            if nodes[parent].name == name { return true }
            parent = nodes[parent].parentIndex
            remaining -= 1
        }
        return false
    }

    private func parseValue(_ attribute: Attribute, from values: Data) throws -> Value? {
        guard attribute.dataOffset >= 0, attribute.length >= 0,
              attribute.dataOffset <= values.count,
              attribute.length <= values.count - attribute.dataOffset else {
            throw ReaderError.malformed("attribute value is outside the value table")
        }
        let bytes = values.subdata(in: attribute.dataOffset..<(attribute.dataOffset + attribute.length))
        switch attribute.type {
        case 19:
            return .boolean(bytes.first != 0)
        case 20, 21, 22, 23, 29, 30:
            let trimmed = bytes.dropLast(bytes.reversed().prefix { $0 == 0 }.count)
            guard let value = String(data: trimmed, encoding: .utf8) else {
                throw ReaderError.malformed("invalid UTF-8 attribute")
            }
            return .string(value)
        case 24:
            guard bytes.count >= 8 else { throw ReaderError.malformed("short UInt64 attribute") }
            return .unsigned(bytes.readUInt64(at: 0))
        case 26, 32:
            guard bytes.count >= 8 else { throw ReaderError.malformed("short Int64 attribute") }
            return .signed(bytes.readInt64(at: 0))
        case 31:
            guard bytes.count == 16 else { throw ReaderError.malformed("invalid UUID attribute") }
            return .string(Self.formatLarianUUID(bytes))
        default:
            return nil
        }
    }

    private func resolveName(_ reference: UInt32, names: [[String]]) throws -> String {
        let bucket = Int(reference >> 16)
        let offset = Int(reference & 0xffff)
        guard names.indices.contains(bucket), names[bucket].indices.contains(offset) else {
            throw ReaderError.malformed("invalid name reference")
        }
        return names[bucket][offset]
    }

    private static func formatLarianUUID(_ data: Data) -> String {
        let bytes = Array(data)
        let order = [3, 2, 1, 0, 5, 4, 7, 6, 9, 8, 11, 10, 13, 12, 15, 14]
        let hex = order.map { String(format: "%02x", bytes[$0]) }
        return hex[0...3].joined() + "-" + hex[4...5].joined() + "-"
            + hex[6...7].joined() + "-" + hex[8...9].joined() + "-" + hex[10...15].joined()
    }

    private func decompressApple(
        _ data: Data,
        expectedSize: Int,
        algorithm: compression_algorithm
    ) throws -> Data {
        guard expectedSize > 0 else { throw ReaderError.decompressionFailed }
        var result = Data(count: expectedSize)
        let decoded = result.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let destinationAddress = destination.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let sourceAddress = source.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
                return compression_decode_buffer(
                    destinationAddress,
                    expectedSize,
                    sourceAddress,
                    data.count,
                    nil,
                    algorithm
                )
            }
        }
        guard decoded == expectedSize else { throw ReaderError.decompressionFailed }
        result.count = decoded
        return result
    }

    private func decompressZstandard(_ data: Data, expectedSize: Int) throws -> Data {
        let reader = BufferedMemoryStream(startData: data)
        let writer = LSFBoundedWriteStream(maximumBytes: expectedSize)
        do {
            try ZSTD.decompress(reader: reader, writer: writer, config: .zstd)
        } catch {
            throw ReaderError.decompressionFailed
        }
        guard writer.data.count == expectedSize else { throw ReaderError.decompressionFailed }
        return writer.data
    }

    private func decompressLZ4Frame(_ data: Data, expectedSize: Int) throws -> Data {
        let reader = BufferedMemoryStream(startData: data)
        let writer = LSFBoundedWriteStream(maximumBytes: expectedSize)
        do {
            try LZ4.decompress(reader: reader, writer: writer, config: .default)
        } catch {
            throw ReaderError.decompressionFailed
        }
        guard writer.data.count == expectedSize else { throw ReaderError.decompressionFailed }
        return writer.data
    }
}

private struct BinaryCursor {
    let data: Data
    private(set) var offset = 0

    var isAtEnd: Bool { offset == data.count }

    mutating func readUInt8() throws -> UInt8 {
        guard offset < data.count else { throw LarianSaveMetadataReader.ReaderError.malformed("unexpected end of data") }
        defer { offset += 1 }
        return data[offset]
    }

    mutating func readUInt16() throws -> UInt16 {
        let bytes = try readData(count: 2)
        return bytes.readUInt16(at: 0)
    }

    mutating func readUInt32() throws -> UInt32 {
        let bytes = try readData(count: 4)
        return bytes.readUInt32(at: 0)
    }

    mutating func readInt32() throws -> Int {
        Int(Int32(bitPattern: try readUInt32()))
    }

    mutating func readData(count: Int) throws -> Data {
        guard count >= 0, offset <= data.count, count <= data.count - offset else {
            throw LarianSaveMetadataReader.ReaderError.malformed("unexpected end of data")
        }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }
}

private final class LSFBoundedWriteStream: WriteableStream {
    private let maximumBytes: Int
    private(set) var data = Data()

    init(maximumBytes: Int) {
        self.maximumBytes = maximumBytes
        data.reserveCapacity(maximumBytes)
    }

    func write(_ bytes: UnsafePointer<UInt8>, length: Int) -> Int {
        guard length >= 0, length <= maximumBytes, data.count <= maximumBytes - length else { return 0 }
        data.append(bytes, count: length)
        return length
    }
}
