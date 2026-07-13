// SPDX-License-Identifier: GPL-3.0-or-later

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
        case unsafePath(String)
        case limitExceeded(String)
        case unsupportedArchivePart(UInt8)

        var errorDescription: String? {
            switch self {
            case .invalidSignature: return "Not a valid LSPK archive (bad signature)"
            case .unsupportedVersion(let v): return "Unsupported LSPK version: \(v)"
            case .fileListReadFailed: return "Failed to read file list from archive"
            case .decompressionFailed: return "Failed to decompress archive data"
            case .fileNotFound(let name): return "File not found in archive: \(name)"
            case .readError(let msg): return "Read error: \(msg)"
            case .unsafePath(let path): return "Unsafe path in archive: \(path)"
            case .limitExceeded(let msg): return "Archive safety limit exceeded: \(msg)"
            case .unsupportedArchivePart(let part):
                return "Split PAK archive part \(part) is not supported"
            }
        }
    }

    struct Limits: Sendable {
        let maximumFileCount: Int
        let maximumFileListBytes: Int
        let maximumCompressedEntryBytes: Int
        let maximumUncompressedEntryBytes: Int
        let maximumTotalExtractionBytes: UInt64

        static let `default` = Limits(
            maximumFileCount: 200_000,
            maximumFileListBytes: 64 * 1_024 * 1_024,
            maximumCompressedEntryBytes: 512 * 1_024 * 1_024,
            maximumUncompressedEntryBytes: 512 * 1_024 * 1_024,
            maximumTotalExtractionBytes: 8 * 1_024 * 1_024 * 1_024
        )
    }

    // MARK: - LSPK Structures

    struct PakHeader: Sendable {
        let version: UInt32
        let fileListOffset: UInt64
        let fileListSize: UInt32
        let flags: UInt8
        let priority: UInt8
        let md5: Data     // 16 bytes
        let numParts: UInt16

        var isSolid: Bool { flags & 0x04 != 0 }
    }

    struct FileEntry: Identifiable, Sendable {
        let name: String
        let offset: UInt64
        let archivePart: UInt8
        let flags: UInt8
        let sizeOnDisk: UInt32
        let uncompressedSize: UInt32

        var id: String { name }

        var compressionMethod: CompressionType {
            CompressionType(rawValue: flags & 0x0F) ?? .none
        }

        /// Some valid legacy PAK writers encode an uncompressed entry with a zero
        /// uncompressed-size field. In that representation, the stored byte count
        /// is also the extracted byte count.
        var effectiveUncompressedSize: UInt64 {
            if compressionMethod == .none && uncompressedSize == 0 {
                return UInt64(sizeOnDisk)
            }
            return UInt64(uncompressedSize)
        }
    }

    enum CompressionType: UInt8, Sendable {
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
    static func listFiles(at url: URL, limits: Limits = .default) throws -> [FileEntry] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        return try readFileEntries(handle: handle, limits: limits)
    }

    /// Extract a specific file from the `.pak` by name path (e.g., "Mods/MyMod/meta.lsx").
    static func extractFile(
        named targetPath: String,
        from url: URL,
        limits: Limits = .default
    ) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        let (header, entries, fileLength) = try readHeaderAndEntries(
            handle: handle,
            limits: limits
        )

        guard let entry = entries.first(where: { $0.name == targetPath }) else {
            throw PakError.fileNotFound(targetPath)
        }

        return try readFileData(
            handle: handle,
            entry: entry,
            header: header,
            fileLength: fileLength,
            limits: limits
        )
    }

    /// Extract all files from a `.pak` archive to a destination folder.
    static func extractAll(
        from pakURL: URL,
        to destinationFolder: URL,
        limits: Limits = .default
    ) throws {
        let handle = try FileHandle(forReadingFrom: pakURL)
        defer { handle.closeFile() }

        let (header, entries, fileLength) = try readHeaderAndEntries(
            handle: handle,
            limits: limits
        )

        var totalSize: UInt64 = 0
        for entry in entries {
            let (nextTotal, overflow) = totalSize.addingReportingOverflow(
                entry.effectiveUncompressedSize
            )
            guard !overflow, nextTotal <= limits.maximumTotalExtractionBytes else {
                throw PakError.limitExceeded("total extracted data")
            }
            totalSize = nextTotal
        }

        for entry in entries {
            try Task.checkCancellation()
            let fileURL = try safeExtractionURL(for: entry.name, in: destinationFolder)
            let data = try readFileData(
                handle: handle,
                entry: entry,
                header: header,
                fileLength: fileLength,
                limits: limits
            )

            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            try data.write(to: fileURL, options: .atomic)
        }
    }

    /// Find and extract `meta.lsx` from a `.pak` file.
    /// Searches for files matching the pattern `Mods/*/meta.lsx`.
    static func extractMetaLsx(
        from url: URL,
        preferredFolder: String? = nil,
        limits: Limits = .default
    ) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }

        let (header, entries, fileLength) = try readHeaderAndEntries(
            handle: handle,
            limits: limits
        )

        let metadataEntries = entries.filter { isMetaLsx(path: $0.name) }
        guard !metadataEntries.isEmpty else {
            throw PakError.fileNotFound("Mods/*/meta.lsx")
        }

        // Some packaged mods contain copies of built-in game metadata alongside their own.
        // Prefer the metadata folder matching the PAK filename instead of blindly taking the
        // first `meta.lsx` (which can otherwise misidentify the mod as Gustav or GustavX).
        let entry = preferredFolder.flatMap { preferredFolder in
            metadataEntries.first {
                metaFolder(path: $0.name)?.caseInsensitiveCompare(preferredFolder) == .orderedSame
            }
        } ?? metadataEntries[0]

        return try readFileData(
            handle: handle,
            entry: entry,
            header: header,
            fileLength: fileLength,
            limits: limits
        )
    }

    /// Check whether a `.pak` contains Script Extender scripts.
    static func containsScriptExtender(at url: URL) -> Bool {
        guard let entries = try? listFiles(at: url) else { return false }
        return entries.contains { $0.name.contains("ScriptExtender/") }
    }

    /// Inspect a `.pak` archive and return both its header and file entries.
    /// Used by the PAK Inspector tool to display archive internals.
    static func inspectPak(
        at url: URL,
        limits: Limits = .default
    ) throws -> (header: PakHeader, entries: [FileEntry]) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { handle.closeFile() }
        let (header, entries, _) = try readHeaderAndEntries(handle: handle, limits: limits)
        return (header, entries)
    }

    // MARK: - Internal Reading

    private static func readHeaderAndEntries(
        handle: FileHandle,
        limits: Limits
    ) throws -> (PakHeader, [FileEntry], UInt64) {
        let fileLength = try handle.seekToEnd()
        let header = try readHeader(handle: handle, fileLength: fileLength, limits: limits)
        let entries = try readFileList(
            handle: handle,
            header: header,
            fileLength: fileLength,
            limits: limits
        )
        return (header, entries, fileLength)
    }

    private static func readFileEntries(handle: FileHandle, limits: Limits) throws -> [FileEntry] {
        let (_, entries, _) = try readHeaderAndEntries(handle: handle, limits: limits)
        return entries
    }

    private static func readHeader(
        handle: FileHandle,
        fileLength: UInt64,
        limits: Limits
    ) throws -> PakHeader {
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

        guard fileListSize <= limits.maximumFileListBytes else {
            throw PakError.limitExceeded("file list is \(fileListSize) bytes")
        }
        guard containsRange(offset: fileListOffset, size: 8, in: fileLength) else {
            throw PakError.fileListReadFailed
        }
        if fileListSize > 0,
           !containsRange(offset: fileListOffset, size: UInt64(fileListSize), in: fileLength) {
            throw PakError.fileListReadFailed
        }

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

    private static func readFileList(
        handle: FileHandle,
        header: PakHeader,
        fileLength: UInt64,
        limits: Limits
    ) throws -> [FileEntry] {
        handle.seek(toFileOffset: header.fileListOffset)

        // V18 file list: first 4 bytes = numFiles, next 4 bytes = compressedSize
        guard let preamble = try handle.read(upToCount: 8),
              preamble.count == 8 else {
            throw PakError.fileListReadFailed
        }

        let numFiles = Int(preamble.readUInt32(at: 0))
        let compressedSize = Int(preamble.readUInt32(at: 4))

        guard numFiles > 0, numFiles <= limits.maximumFileCount else {
            throw PakError.limitExceeded("file count is \(numFiles)")
        }
        let (compressedDataOffset, offsetOverflow) = header.fileListOffset
            .addingReportingOverflow(8)
        guard !offsetOverflow,
              compressedSize > 0,
              compressedSize <= limits.maximumFileListBytes,
              containsRange(
                offset: compressedDataOffset,
                size: UInt64(compressedSize),
                in: fileLength
              ) else {
            throw PakError.fileListReadFailed
        }

        guard let compressedData = try handle.read(upToCount: compressedSize),
              compressedData.count == compressedSize else {
            throw PakError.fileListReadFailed
        }

        let (expectedSize, overflow) = numFiles.multipliedReportingOverflow(by: fileEntrySize)
        guard !overflow, expectedSize <= limits.maximumFileListBytes else {
            throw PakError.limitExceeded("expanded file list is too large")
        }
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

        guard entryData.count == expectedSize else {
            throw PakError.fileListReadFailed
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

            guard !name.isEmpty else {
                throw PakError.unsafePath(name)
            }
            let effectiveUncompressedSize: UInt64 =
                flags & 0x0F == CompressionType.none.rawValue && uncompressedSize == 0
                ? UInt64(sizeOnDisk)
                : UInt64(uncompressedSize)
            guard sizeOnDisk <= limits.maximumCompressedEntryBytes,
                  effectiveUncompressedSize <= UInt64(limits.maximumUncompressedEntryBytes) else {
                throw PakError.limitExceeded("entry \(name) is too large")
            }
            if archivePart == 0,
               !containsRange(offset: offset, size: UInt64(sizeOnDisk), in: fileLength) {
                throw PakError.readError("File data range is outside the archive for \(name)")
            }

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

    private static func readFileData(
        handle: FileHandle,
        entry: FileEntry,
        header: PakHeader,
        fileLength: UInt64,
        limits: Limits
    ) throws -> Data {
        guard entry.archivePart == 0 else {
            throw PakError.unsupportedArchivePart(entry.archivePart)
        }
        guard entry.sizeOnDisk <= limits.maximumCompressedEntryBytes,
              entry.effectiveUncompressedSize <= UInt64(limits.maximumUncompressedEntryBytes) else {
            throw PakError.limitExceeded("entry \(entry.name) is too large")
        }
        guard containsRange(
            offset: entry.offset,
            size: UInt64(entry.sizeOnDisk),
            in: fileLength
        ) else {
            throw PakError.readError("File data range is outside the archive for \(entry.name)")
        }
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
            // Older tools commonly write raw entries with an expanded size of zero.
            // The bytes are not compressed, so the stored size is authoritative.
            guard entry.uncompressedSize == 0 else {
                throw PakError.decompressionFailed
            }
            return compressedData
        case .zlib:
            algorithm = COMPRESSION_ZLIB
        case .lz4:
            algorithm = header.isSolid ? COMPRESSION_LZ4 : COMPRESSION_LZ4_RAW
        }

        guard let decompressed = decompress(
            compressedData,
            expectedSize: Int(entry.uncompressedSize),
            algorithm: algorithm
        ), decompressed.count == Int(entry.uncompressedSize) else {
            throw PakError.decompressionFailed
        }

        return decompressed
    }

    // MARK: - Helpers

    private static func isMetaLsx(path: String) -> Bool {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.hasPrefix("Mods/") && normalized.hasSuffix("/meta.lsx")
    }

    private static func metaFolder(path: String) -> String? {
        let components = path.replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 3,
              components[0].caseInsensitiveCompare("Mods") == .orderedSame,
              components[2].caseInsensitiveCompare("meta.lsx") == .orderedSame else {
            return nil
        }
        return String(components[1])
    }

    /// Resolves an archive path and proves it remains inside the extraction root.
    static func safeExtractionURL(for entryName: String, in destinationFolder: URL) throws -> URL {
        do {
            return try ArchivePathValidator.safeDestination(
                for: entryName,
                in: destinationFolder
            )
        } catch {
            throw PakError.unsafePath(entryName)
        }
    }

    private static func containsRange(offset: UInt64, size: UInt64, in length: UInt64) -> Bool {
        let (end, overflow) = offset.addingReportingOverflow(size)
        return !overflow && offset <= length && end <= length
    }

    private static func decompress(_ data: Data, expectedSize: Int, algorithm: compression_algorithm) -> Data? {
        guard expectedSize > 0 else { return nil }
        let bufferSize = expectedSize
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

        guard result == expectedSize else { return nil }
        decompressed.count = result
        return decompressed
    }
}

// MARK: - Data Binary Reading Extensions

extension Data {
    func readUInt16(at offset: Int) -> UInt16 {
        guard offset + 2 <= count else { return 0 }
        var value: UInt16 = 0
        _ = withUnsafeBytes { buf in
            memcpy(&value, buf.baseAddress! + offset, 2)
        }
        return UInt16(littleEndian: value)
    }

    func readUInt32(at offset: Int) -> UInt32 {
        guard offset + 4 <= count else { return 0 }
        var value: UInt32 = 0
        _ = withUnsafeBytes { buf in
            memcpy(&value, buf.baseAddress! + offset, 4)
        }
        return UInt32(littleEndian: value)
    }

    func readUInt64(at offset: Int) -> UInt64 {
        guard offset + 8 <= count else { return 0 }
        var value: UInt64 = 0
        _ = withUnsafeBytes { buf in
            memcpy(&value, buf.baseAddress! + offset, 8)
        }
        return UInt64(littleEndian: value)
    }

    func readInt64(at offset: Int) -> Int64 {
        guard offset + 8 <= count else { return 0 }
        var value: Int64 = 0
        _ = withUnsafeBytes { buf in
            memcpy(&value, buf.baseAddress! + offset, 8)
        }
        return Int64(littleEndian: value)
    }
}
