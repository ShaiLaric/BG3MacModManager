import Foundation
import Compression

/// Reads Larian LSPK v18 `.pak` archive files to extract mod metadata.
///
/// The LSPK v18 format structure:
/// - 4 bytes: "LSPK" magic signature
/// - Header: version, file list offset/size, flags, priority, MD5, numParts
/// - File entries: name (256 bytes), offset, compression, sizes
/// - File data: individually or solid-compressed file contents
final class PakReader {

    enum PakError: Error, LocalizedError {
        case invalidSignature
        case unsupportedVersion(UInt32)
        case fileListReadFailed
        case decompressionFailed
        case fileNotFound(String)
        case readError(String)

        var errorDescription: String? {
            switch self {
            case .invalidSignature: return "Not a valid LSPK archive (bad signature)"
            case .unsupportedVersion(let v): return "Unsupported LSPK version: \(v)"
            case .fileListReadFailed: return "Failed to read file list from archive"
            case .decompressionFailed: return "Failed to decompress archive data"
            case .fileNotFound(let name): return "File not found in archive: \(name)"
            case .readError(let msg): return "Read error: \(msg)"
            }
        }
    }

    // MARK: - LSPK Structures

    struct PakHeader {
        let version: UInt32
        let fileListOffset: UInt64
        let fileListSize: UInt32
        let flags: UInt8
        let priority: UInt8
        let md5: Data     // 16 bytes
        let numParts: UInt16

        var isSolid: Bool { flags & 0x04 != 0 }
    }

    struct FileEntry {
        let name: String
        let offset: UInt64
        let archivePart: UInt8
        let flags: UInt8
        let sizeOnDisk: UInt32
        let uncompressedSize: UInt32

        var compressionMethod: CompressionType {
            CompressionType(rawValue: flags & 0x0F) ?? .none
        }
    }

    enum CompressionType: UInt8 {
        case none = 0
        case zlib = 1
        case lz4  = 2
    }

    // MARK: - Constants

    private static let signature: [UInt8] = [0x4C, 0x53, 0x50, 0x4B] // "LSPK"
    private static let headerSize = 4 + 8 + 4 + 1 + 1 + 16 + 2  // 36 bytes after signature
    private static let fileEntrySize = 256 + 4 + 2 + 1 + 1 + 4 + 4  // 272 bytes

    // MARK: - Public API

    /// List all files in a `.pak` archive.
    static func listFiles(at url: URL) throws -> [FileEntry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        return try readFileEntries(handle: handle)
    }

    /// Extract a specific file from the `.pak` by name path (e.g., "Mods/MyMod/meta.lsx").
    static func extractFile(named targetPath: String, from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        let (header, entries) = try readHeaderAndEntries(handle: handle)

        guard let entry = entries.first(where: { $0.name == targetPath }) else {
            throw PakError.fileNotFound(targetPath)
        }

        return try readFileData(handle: handle, entry: entry, header: header)
    }

    /// Find and extract `meta.lsx` from a `.pak` file.
    /// Searches for files matching the pattern `Mods/*/meta.lsx`.
    static func extractMetaLsx(from url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        let (header, entries) = try readHeaderAndEntries(handle: handle)

        guard let entry = entries.first(where: { isMetaLsx(path: $0.name) }) else {
            throw PakError.fileNotFound("Mods/*/meta.lsx")
        }

        return try readFileData(handle: handle, entry: entry, header: header)
    }

    /// Check whether a `.pak` contains Script Extender scripts.
    static func containsScriptExtender(at url: URL) -> Bool {
        guard let entries = try? listFiles(at: url) else { return false }
        return entries.contains { $0.name.contains("ScriptExtender/") }
    }

    // MARK: - Internal Reading

    private static func readHeaderAndEntries(handle: FileHandle) throws -> (PakHeader, [FileEntry]) {
        let header = try readHeader(handle: handle)
        let entries = try readFileList(handle: handle, header: header)
        return (header, entries)
    }

    private static func readFileEntries(handle: FileHandle) throws -> [FileEntry] {
        let header = try readHeader(handle: handle)
        return try readFileList(handle: handle, header: header)
    }

    private static func readHeader(handle: FileHandle) throws -> PakHeader {
        handle.seek(toFileOffset: 0)
        guard let sigData = try handle.read(upToCount: 4),
              sigData.count == 4 else {
            throw PakError.readError("Cannot read signature")
        }

        guard Array(sigData) == signature else {
            throw PakError.invalidSignature
        }

        guard let headerData = try handle.read(upToCount: headerSize),
              headerData.count == headerSize else {
            throw PakError.readError("Cannot read header")
        }

        let version = headerData.readUInt32(at: 0)
        guard version == 18 || version == 16 || version == 15 else {
            throw PakError.unsupportedVersion(version)
        }

        let fileListOffset = headerData.readUInt64(at: 4)
        let fileListSize   = headerData.readUInt32(at: 12)
        let flags          = headerData[16]
        let priority       = headerData[17]
        let md5            = headerData[18..<34]
        let numParts       = headerData.readUInt16(at: 34)

        return PakHeader(
            version: version,
            fileListOffset: fileListOffset,
            fileListSize: fileListSize,
            flags: flags,
            priority: priority,
            md5: Data(md5),
            numParts: numParts
        )
    }

    private static func readFileList(handle: FileHandle, header: PakHeader) throws -> [FileEntry] {
        handle.seek(toFileOffset: header.fileListOffset)

        // V18 file list: first 4 bytes = numFiles, next 4 bytes = compressedSize
        guard let preamble = try handle.read(upToCount: 8),
              preamble.count == 8 else {
            throw PakError.fileListReadFailed
        }

        let numFiles = Int(preamble.readUInt32(at: 0))
        let compressedSize = Int(preamble.readUInt32(at: 4))

        guard numFiles > 0, numFiles < 1_000_000 else {
            throw PakError.fileListReadFailed
        }

        guard let compressedData = try handle.read(upToCount: compressedSize),
              compressedData.count == compressedSize else {
            throw PakError.fileListReadFailed
        }

        let expectedSize = numFiles * fileEntrySize
        let entryData: Data

        if compressedSize == expectedSize {
            // Data is not compressed
            entryData = compressedData
        } else if header.isSolid {
            // Solid: try LZ4 frame first, fall back to raw LZ4
            if let decompressed = decompress(compressedData, expectedSize: expectedSize, algorithm: COMPRESSION_LZ4) {
                entryData = decompressed
            } else if let decompressed = decompress(compressedData, expectedSize: expectedSize, algorithm: COMPRESSION_LZ4_RAW) {
                entryData = decompressed
            } else {
                throw PakError.decompressionFailed
            }
        } else {
            // Non-solid: try raw LZ4 first, fall back to frame LZ4
            if let decompressed = decompress(compressedData, expectedSize: expectedSize, algorithm: COMPRESSION_LZ4_RAW) {
                entryData = decompressed
            } else if let decompressed = decompress(compressedData, expectedSize: expectedSize, algorithm: COMPRESSION_LZ4) {
                entryData = decompressed
            } else {
                throw PakError.decompressionFailed
            }
        }

        // Parse file entries
        var entries: [FileEntry] = []
        entries.reserveCapacity(numFiles)

        for i in 0..<numFiles {
            let base = i * fileEntrySize
            guard base + fileEntrySize <= entryData.count else { break }

            let nameData = entryData[base..<(base + 256)]
            let name = String(data: Data(nameData), encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\0")) ?? ""

            let offsetLow  = UInt64(entryData.readUInt32(at: base + 256))
            let offsetHigh = UInt64(entryData.readUInt16(at: base + 260))
            let offset     = offsetLow | (offsetHigh << 32)

            let archivePart      = entryData[base + 262]
            let flags            = entryData[base + 263]
            let sizeOnDisk       = entryData.readUInt32(at: base + 264)
            let uncompressedSize = entryData.readUInt32(at: base + 268)

            entries.append(FileEntry(
                name: name,
                offset: offset,
                archivePart: archivePart,
                flags: flags,
                sizeOnDisk: sizeOnDisk,
                uncompressedSize: uncompressedSize
            ))
        }

        return entries
    }

    private static func readFileData(handle: FileHandle, entry: FileEntry, header: PakHeader) throws -> Data {
        handle.seek(toFileOffset: entry.offset)

        guard let compressedData = try handle.read(upToCount: Int(entry.sizeOnDisk)),
              compressedData.count == Int(entry.sizeOnDisk) else {
            throw PakError.readError("Could not read file data for \(entry.name)")
        }

        if entry.sizeOnDisk == entry.uncompressedSize {
            return compressedData
        }

        let algorithm: compression_algorithm
        switch entry.compressionMethod {
        case .none:
            return compressedData
        case .zlib:
            algorithm = COMPRESSION_ZLIB
        case .lz4:
            algorithm = header.isSolid ? COMPRESSION_LZ4 : COMPRESSION_LZ4_RAW
        }

        guard let decompressed = decompress(compressedData, expectedSize: Int(entry.uncompressedSize), algorithm: algorithm) else {
            throw PakError.decompressionFailed
        }

        return decompressed
    }

    // MARK: - Helpers

    private static func isMetaLsx(path: String) -> Bool {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.hasPrefix("Mods/") && normalized.hasSuffix("/meta.lsx")
    }

    private static func decompress(_ data: Data, expectedSize: Int, algorithm: compression_algorithm) -> Data? {
        // Allow generous buffer (expected size + some slack)
        let bufferSize = max(expectedSize, data.count * 4)
        var decompressed = Data(count: bufferSize)

        let result = decompressed.withUnsafeMutableBytes { destBuffer in
            data.withUnsafeBytes { srcBuffer in
                guard let destPtr = destBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let srcPtr = srcBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                return compression_decode_buffer(
                    destPtr, bufferSize,
                    srcPtr, data.count,
                    nil,
                    algorithm
                )
            }
        }

        guard result > 0 else { return nil }
        decompressed.count = result
        return decompressed
    }
}

// MARK: - Data Binary Reading Extensions

extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        let range = offset..<(offset + 2)
        guard range.upperBound <= count else { return 0 }
        return self[range].withUnsafeBytes { $0.load(as: UInt16.self).littleEndian }
    }

    func readUInt32(at offset: Int) -> UInt32 {
        let range = offset..<(offset + 4)
        guard range.upperBound <= count else { return 0 }
        return self[range].withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    }

    func readUInt64(at offset: Int) -> UInt64 {
        let range = offset..<(offset + 8)
        guard range.upperBound <= count else { return 0 }
        return self[range].withUnsafeBytes { $0.load(as: UInt64.self).littleEndian }
    }

    func readInt64(at offset: Int) -> Int64 {
        let range = offset..<(offset + 8)
        guard range.upperBound <= count else { return 0 }
        return self[range].withUnsafeBytes { $0.load(as: Int64.self).littleEndian }
    }
}
