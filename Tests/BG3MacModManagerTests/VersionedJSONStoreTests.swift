// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class VersionedJSONStoreTests: XCTestCase {
    private struct Payload: Codable, Equatable {
        var name: String
        var count: Int
    }

    private var temporaryDirectory: URL!
    private var documentURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VersionedJSONStoreTests-\(UUID().uuidString)")
        documentURL = temporaryDirectory.appendingPathComponent("document.json")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testMissingDocumentReturnsNil() throws {
        let store = VersionedJSONStore<Payload>(url: documentURL, currentSchemaVersion: 1)
        XCTAssertNil(try store.load())
    }

    func testSaveAndLoadRoundTrip() throws {
        let store = VersionedJSONStore<Payload>(url: documentURL, currentSchemaVersion: 1)
        let expected = Payload(name: "rules", count: 4)

        try store.save(expected)

        XCTAssertEqual(try store.load(), expected)
        let raw = try String(contentsOf: documentURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("\"schemaVersion\" : 1"))
    }

    func testCorruptDocumentIsNotSilentlyReset() throws {
        try Data("not-json".utf8).write(to: documentURL)
        let store = VersionedJSONStore<Payload>(url: documentURL, currentSchemaVersion: 1)

        XCTAssertThrowsError(try store.load()) { error in
            guard case VersionedJSONStore<Payload>.StoreError.corrupt = error else {
                return XCTFail("Expected corrupt error, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: documentURL), Data("not-json".utf8))
    }

    func testNewerSchemaIsRejected() throws {
        try Data("""
        {"schemaVersion": 9, "payload": {"name": "future", "count": 1}}
        """.utf8).write(to: documentURL)
        let store = VersionedJSONStore<Payload>(url: documentURL, currentSchemaVersion: 2)

        XCTAssertThrowsError(try store.load()) { error in
            guard case let VersionedJSONStore<Payload>.StoreError.unsupportedVersion(stored, supported, _) = error else {
                return XCTFail("Expected unsupported-version error, got \(error)")
            }
            XCTAssertEqual(stored, 9)
            XCTAssertEqual(supported, 2)
        }
    }

    func testExplicitMigrationRewritesCurrentSchema() throws {
        try Data("""
        {"schemaVersion": 1, "payload": {"title": "legacy"}}
        """.utf8).write(to: documentURL)
        let store = VersionedJSONStore<Payload>(url: documentURL, currentSchemaVersion: 2)

        let migrated = try store.load { version, data in
            XCTAssertEqual(version, 1)
            XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("legacy"))
            return Payload(name: "migrated", count: 2)
        }

        XCTAssertEqual(migrated, Payload(name: "migrated", count: 2))
        let raw = try String(contentsOf: documentURL, encoding: .utf8)
        XCTAssertTrue(raw.contains("\"schemaVersion\" : 2"))
    }

    func testResetPreservesUnreadableBytes() throws {
        let invalidData = Data("broken-document".utf8)
        try invalidData.write(to: documentURL)
        let store = VersionedJSONStore<Payload>(url: documentURL, currentSchemaVersion: 1)

        let backupURL = try XCTUnwrap(
            store.resetPreservingExisting(with: Payload(name: "fresh", count: 1))
        )

        XCTAssertEqual(try Data(contentsOf: backupURL), invalidData)
        XCTAssertEqual(try store.load(), Payload(name: "fresh", count: 1))
    }
}
