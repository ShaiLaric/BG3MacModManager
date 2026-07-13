// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
import ZSTD
@testable import BG3MacModManager

final class PakReaderTests: XCTestCase {

    var tempFiles: [URL] = []

    override func tearDown() {
        for url in tempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        tempFiles.removeAll()
        super.tearDown()
    }

    /// Write binary data to a temporary file and track it for cleanup.
    private func writeTempBinary(name: String, data: Data) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bg3test_\(UUID().uuidString)_\(name)")
        try! data.write(to: url)
        tempFiles.append(url)
        return url
    }

    // MARK: - Signature Validation

    func testInvalidSignatureThrows() {
        // 4 bytes of wrong signature + 36 bytes of header padding = 40 bytes total
        var data = Data([0x00, 0x00, 0x00, 0x00])
        data.append(Data(count: 36))
        let url = writeTempBinary(name: "bad_sig.pak", data: data)

        XCTAssertThrowsError(try PakReader.listFiles(at: url)) { error in
            guard let pakError = error as? PakReader.PakError else {
                XCTFail("Expected PakError, got \(error)")
                return
            }
            if case .invalidSignature = pakError {
                // Expected
            } else {
                XCTFail("Expected invalidSignature, got \(pakError)")
            }
        }
    }

    func testTooSmallDataThrows() {
        let data = Data([0x4C, 0x53]) // Only 2 bytes, not enough for signature
        let url = writeTempBinary(name: "tiny.pak", data: data)

        XCTAssertThrowsError(try PakReader.listFiles(at: url))
    }

    func testEmptyFileThrows() {
        let data = Data()
        let url = writeTempBinary(name: "empty.pak", data: data)

        XCTAssertThrowsError(try PakReader.listFiles(at: url))
    }

    // MARK: - Version Validation

    func testUnsupportedVersionThrows() {
        // Valid "LSPK" signature + version 99
        var data = Data([0x4C, 0x53, 0x50, 0x4B]) // "LSPK"
        // Version 99 as UInt32 little-endian
        data.append(contentsOf: [0x63, 0x00, 0x00, 0x00])
        // Pad remaining header bytes (32 bytes to reach headerSize of 36)
        data.append(Data(count: 32))
        let url = writeTempBinary(name: "bad_version.pak", data: data)

        XCTAssertThrowsError(try PakReader.listFiles(at: url)) { error in
            guard let pakError = error as? PakReader.PakError else {
                XCTFail("Expected PakError, got \(error)")
                return
            }
            if case .unsupportedVersion(let v) = pakError {
                XCTAssertEqual(v, 99)
            } else {
                XCTFail("Expected unsupportedVersion, got \(pakError)")
            }
        }
    }

    func testVersion18PassesVersionCheck() {
        // Valid signature + version 18 but zeroed file list offset
        // Should fail on file list read, not on version check
        var data = Data([0x4C, 0x53, 0x50, 0x4B]) // "LSPK"
        data.append(contentsOf: [0x12, 0x00, 0x00, 0x00]) // version 18
        data.append(Data(count: 32)) // rest of header zeroed (4 + 32 = 36 = headerSize)
        let url = writeTempBinary(name: "v18.pak", data: data)

        XCTAssertThrowsError(try PakReader.listFiles(at: url)) { error in
            guard let pakError = error as? PakReader.PakError else {
                // FileHandle or other error is also acceptable here
                return
            }
            // Should NOT be unsupportedVersion
            if case .unsupportedVersion = pakError {
                XCTFail("Version 18 should not throw unsupportedVersion")
            }
        }
    }

    func testOversizedFileListIsRejectedBeforeAllocation() {
        var data = Data([0x4C, 0x53, 0x50, 0x4B])
        data.append(littleEndianBytes(UInt32(18)))
        data.append(littleEndianBytes(UInt64(40)))
        data.append(littleEndianBytes(UInt32(64 * 1_024 * 1_024 + 1)))
        data.append(Data(count: 20))
        let url = writeTempBinary(name: "oversized-list.pak", data: data)

        XCTAssertThrowsError(try PakReader.listFiles(at: url)) { error in
            guard case PakReader.PakError.limitExceeded = error else {
                XCTFail("Expected limitExceeded, got \(error)")
                return
            }
        }
    }

    // MARK: - Nonexistent File

    func testListFilesOnNonexistentPathThrows() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).pak")
        XCTAssertThrowsError(try PakReader.listFiles(at: url))
    }

    func testExtractFileFromNonexistentPathThrows() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).pak")
        XCTAssertThrowsError(try PakReader.extractFile(named: "meta.lsx", from: url))
    }

    // MARK: - containsScriptExtender Graceful Handling

    func testContainsScriptExtenderReturnsFalseForInvalidFile() {
        let data = Data([0x00, 0x01, 0x02, 0x03])
        let url = writeTempBinary(name: "not_a_pak.bin", data: data)
        XCTAssertFalse(PakReader.containsScriptExtender(at: url))
    }

    func testContainsScriptExtenderReturnsFalseForNonexistentFile() {
        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).pak")
        XCTAssertFalse(PakReader.containsScriptExtender(at: url))
    }

    // MARK: - Legacy Uncompressed Entries

    func testExtractsUncompressedEntryWhoseExpandedSizeIsZero() throws {
        let metadata = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <save><region id="Config"><node id="root"><children>
        <node id="ModuleInfo"><attribute id="UUID" type="guid" value="755a8a72-407f-4f0d-9a33-274ac0f0b53d"/></node>
        </children></node></region></save>
        """.utf8)
        let url = writeTempBinary(
            name: "legacy-uncompressed.pak",
            data: makeSingleEntryPak(
                name: "Mods/BG3MCM/meta.lsx",
                contents: metadata,
                uncompressedSize: 0,
                flags: 0
            )
        )

        XCTAssertEqual(try PakReader.extractMetaLsx(from: url), metadata)
    }

    func testLegacyZeroExpandedSizeStillCountsAgainstExtractionLimit() {
        let metadata = Data(repeating: 0x41, count: 32)
        let url = writeTempBinary(
            name: "legacy-uncompressed-limit.pak",
            data: makeSingleEntryPak(
                name: "Mods/Test/meta.lsx",
                contents: metadata,
                uncompressedSize: 0,
                flags: 0
            )
        )
        let limits = PakReader.Limits(
            maximumFileCount: 10,
            maximumFileListBytes: 1_024,
            maximumCompressedEntryBytes: 1_024,
            maximumUncompressedEntryBytes: 16,
            maximumTotalExtractionBytes: 1_024
        )

        XCTAssertThrowsError(try PakReader.extractMetaLsx(from: url, limits: limits)) { error in
            guard case PakReader.PakError.limitExceeded = error else {
                XCTFail("Expected limitExceeded, got \(error)")
                return
            }
        }
    }

    func testPreferredMetadataFolderWinsWhenPakContainsBuiltInMetadata() throws {
        let gustavMetadata = Data("<save><node id=\"ModuleInfo\"><attribute id=\"Name\" value=\"Gustav\"/></node></save>".utf8)
        let modMetadata = Data("<save><node id=\"ModuleInfo\"><attribute id=\"Name\" value=\"Party Limit Begone\"/></node></save>".utf8)
        let url = writeTempBinary(
            name: "PartyLimitBegone.pak",
            data: makeUncompressedTestPak(entries: [
                ("Mods/Gustav/meta.lsx", gustavMetadata),
                ("Mods/PartyLimitBegone/meta.lsx", modMetadata),
            ])
        )

        XCTAssertEqual(
            try PakReader.extractMetaLsx(
                from: url,
                preferredFolder: "partylimitbegone"
            ),
            modMetadata
        )
        XCTAssertEqual(try PakReader.extractMetaLsx(from: url), gustavMetadata)
    }

    // MARK: - Extraction Path Safety

    func testSafeExtractionPathStaysInsideDestination() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pak-extract-\(UUID().uuidString)")
        let result = try PakReader.safeExtractionURL(
            for: "Mods/Example/meta.lsx",
            in: root
        )
        XCTAssertEqual(result.path, root.appendingPathComponent("Mods/Example/meta.lsx").path)
    }

    func testExtractionRejectsTraversalAbsoluteAndWindowsPaths() {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("pak-extract-\(UUID().uuidString)")
        let unsafePaths = [
            "../../outside.txt",
            "Mods/../outside.txt",
            "/tmp/outside.txt",
            "C:\\outside.txt",
            "Mods//outside.txt",
            "",
        ]

        for path in unsafePaths {
            XCTAssertThrowsError(
                try PakReader.safeExtractionURL(for: path, in: root),
                "Expected unsafe archive path to be rejected: \(path)"
            )
        }
    }

    // MARK: - CompressionType Enum

    func testCompressionTypeNone() {
        XCTAssertEqual(PakReader.CompressionType(rawValue: 0), PakReader.CompressionType.none)
    }

    func testCompressionTypeZlib() {
        XCTAssertEqual(PakReader.CompressionType(rawValue: 1), .zlib)
    }

    func testCompressionTypeLZ4() {
        XCTAssertEqual(PakReader.CompressionType(rawValue: 2), .lz4)
    }

    func testCompressionTypeZstandard() {
        XCTAssertEqual(PakReader.CompressionType(rawValue: 3), .zstd)
    }

    func testExtractsZstandardEntry() throws {
        let contents = Data("modern BG3 save metadata".utf8)
        let compressed = try ZSTD.memory.compress(data: contents)
        let url = writeTempBinary(
            name: "zstandard.pak",
            data: makeSingleEntryPak(
                name: "SaveInfo.json",
                contents: compressed,
                uncompressedSize: UInt32(contents.count),
                flags: 3
            )
        )

        XCTAssertEqual(
            try PakReader.extractFile(named: "SaveInfo.json", from: url),
            contents
        )
    }

    func testZstandardEntryMustMatchDeclaredExpandedSize() throws {
        let contents = Data("metadata".utf8)
        let compressed = try ZSTD.memory.compress(data: contents)
        let url = writeTempBinary(
            name: "zstandard-bad-size.pak",
            data: makeSingleEntryPak(
                name: "SaveInfo.json",
                contents: compressed,
                uncompressedSize: UInt32(contents.count + 1),
                flags: 3
            )
        )

        XCTAssertThrowsError(try PakReader.extractFile(named: "SaveInfo.json", from: url)) { error in
            guard case PakReader.PakError.decompressionFailed = error else {
                XCTFail("Expected decompressionFailed, got \(error)")
                return
            }
        }
    }

    func testCompressionTypeUnknownReturnsNil() {
        XCTAssertNil(PakReader.CompressionType(rawValue: 99))
    }

    // MARK: - PakError Descriptions

    func testPakErrorDescriptions() {
        let errors: [PakReader.PakError] = [
            .invalidSignature,
            .unsupportedVersion(14),
            .fileListReadFailed,
            .decompressionFailed,
            .fileNotFound("meta.lsx"),
            .readError("test error"),
        ]

        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Missing description for \(error)")
            XCTAssertFalse(error.errorDescription!.isEmpty)
        }
    }

    func testPakErrorFileNotFoundIncludesFilename() {
        let error = PakReader.PakError.fileNotFound("Mods/Test/meta.lsx")
        XCTAssertTrue(error.errorDescription!.contains("Mods/Test/meta.lsx"))
    }

    func testPakErrorUnsupportedVersionIncludesVersion() {
        let error = PakReader.PakError.unsupportedVersion(14)
        XCTAssertTrue(error.errorDescription!.contains("14"))
    }

    private func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> Data {
        var value = value.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }

    private func makeSingleEntryPak(
        name: String,
        contents: Data,
        uncompressedSize: UInt32,
        flags: UInt8
    ) -> Data {
        let headerByteCount = 40
        let entryByteCount = 272
        let fileListOffset = UInt64(headerByteCount + contents.count)
        let fileListSize = UInt32(8 + entryByteCount)

        var pak = Data([0x4C, 0x53, 0x50, 0x4B])
        pak.append(littleEndianBytes(UInt32(18)))
        pak.append(littleEndianBytes(fileListOffset))
        pak.append(littleEndianBytes(fileListSize))
        pak.append(contentsOf: [0, 0])
        pak.append(Data(count: 16))
        pak.append(littleEndianBytes(UInt16(1)))
        XCTAssertEqual(pak.count, headerByteCount)

        pak.append(contents)
        pak.append(littleEndianBytes(UInt32(1)))
        pak.append(littleEndianBytes(UInt32(entryByteCount)))

        var entry = Data(name.utf8)
        precondition(entry.count <= 256)
        entry.append(Data(count: 256 - entry.count))
        entry.append(littleEndianBytes(UInt32(headerByteCount)))
        entry.append(littleEndianBytes(UInt16(0)))
        entry.append(contentsOf: [0, flags])
        entry.append(littleEndianBytes(UInt32(contents.count)))
        entry.append(littleEndianBytes(uncompressedSize))
        XCTAssertEqual(entry.count, entryByteCount)
        pak.append(entry)

        return pak
    }
}
