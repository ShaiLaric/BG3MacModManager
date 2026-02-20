// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
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
}
