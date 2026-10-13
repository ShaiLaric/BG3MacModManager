// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import BG3MacModManager

final class PlannedSafetyTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BG3Safety-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testMigrationDoesNotReadCredentialWithoutLegacyValue() {
        let suite = "BG3Credential-\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = TestNexusCredentialStore()
        store.migrateLegacyValueIfNeeded(defaults: defaults)
        XCTAssertEqual(store.readCount, 0)
        defaults.set("legacy-test-key", forKey: "nexusAPIKey")
        store.migrateLegacyValueIfNeeded(defaults: defaults)
        XCTAssertEqual(store.apiKey(), "legacy-test-key")
        XCTAssertNil(defaults.string(forKey: "nexusAPIKey"))
    }

    func testServiceConstructionNeverReadsCredential() {
        let store = TestNexusCredentialStore()
        _ = NexusAPIService(credentialStore: store, cacheURL: root.appendingPathComponent("cache.json"))
        XCTAssertEqual(store.readCount, 0)
    }

    func testBackupsWithinOneSecondHaveDistinctNamesAndCorrectLegacyDate() throws {
        let live = root.appendingPathComponent("settings.lsx")
        let backups = root.appendingPathComponent("Backups")
        try Data("settings".utf8).write(to: live)
        let service = BackupService(modSettingsURL: live, backupsDirectory: backups)
        XCTAssertNotEqual(try service.backupModSettings().id, try service.backupModSettings().id)
        let legacy = backups.appendingPathComponent("modsettings-2026-02-13T03-31-27Z.lsx")
        try Data().write(to: legacy)
        let expected = ISO8601DateFormatter().date(from: "2026-02-13T03:31:27Z")!
        XCTAssertEqual(try service.listBackups().first { $0.url.lastPathComponent == legacy.lastPathComponent }?.date, expected)
    }

    func testRecoveryRetainsSuccessfulExportAndRejectsDifferentLocation() throws {
        let live = root.appendingPathComponent("settings.lsx")
        let snapshot = root.appendingPathComponent("snapshot.json")
        let baseline = root.appendingPathComponent("baseline")
        let service = ModSettingsRecoveryService(settingsURL: live, snapshotURL: snapshot, baselineURL: baseline)
        let first = ModSettingsService().data(activeMods: [makeModInfo(uuid: "a", name: "First")])
        let second = ModSettingsService().data(activeMods: [makeModInfo(uuid: "b", name: "Second")])
        try service.save(first)
        try service.save(second)
        try first.write(to: live, options: .atomic) // An external reset to the older order.
        XCTAssertEqual(try service.savedData(), second)
        XCTAssertThrowsError(try ModSettingsRecoveryService(
            settingsURL: root.appendingPathComponent("other.lsx"), snapshotURL: snapshot, baselineURL: baseline
        ).savedData())
    }

    func testRecoveryPersistenceFailureRollsBackLiveSettingsAndSnapshot() throws {
        let live = root.appendingPathComponent("settings.lsx")
        let snapshot = root.appendingPathComponent("snapshot.json")
        let baseline = root.appendingPathComponent("baseline")
        let service = ModSettingsRecoveryService(settingsURL: live, snapshotURL: snapshot, baselineURL: baseline)
        let first = ModSettingsService().data(activeMods: [])
        let second = ModSettingsService().data(activeMods: [makeModInfo(uuid: "b")])
        try service.save(first)
        try FileManager.default.removeItem(at: baseline)
        let fileManager = FailingCommitFileManager(failingDestination: baseline)
        XCTAssertThrowsError(try service.save(second, fileManager: fileManager))
        XCTAssertEqual(try Data(contentsOf: live), first)
        XCTAssertEqual(try service.savedData(), first)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix(".") }, [])
    }

    func testFinalizeFailureRollsBackReplacementAndDeletion() throws {
        let source = root.appendingPathComponent("new")
        let installed = root.appendingPathComponent("installed")
        let companion = root.appendingPathComponent("companion")
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: installed)
        try Data("metadata".utf8).write(to: companion)
        XCTAssertThrowsError(try TransactionalFileService.replaceFiles([
            .init(source: source, destination: installed),
        ], removing: [companion]) {
            throw NSError(domain: "verification", code: 1)
        })
        XCTAssertEqual(try String(contentsOf: installed), "old")
        XCTAssertEqual(try String(contentsOf: companion), "metadata")
    }

    func testCorruptLegacyStoresAndVersionedDocumentsRejectEdits() throws {
        let corrupt = Data("{recoverable bytes".utf8)
        let notesURL = root.appendingPathComponent("notes.json")
        let urlsURL = root.appendingPathComponent("urls.json")
        let categoriesURL = root.appendingPathComponent("categories.json")
        let versionedURL = root.appendingPathComponent("versioned.json")
        for url in [notesURL, urlsURL, categoriesURL, versionedURL] { try corrupt.write(to: url) }
        let notes = ModNotesService(storageURL: notesURL)
        XCTAssertNotNil(notes.loadError)
        XCTAssertFalse(notes.setNote("new", for: "a"))
        XCTAssertFalse(NexusURLService(storageURL: urlsURL).bulkSetURLs(["a": "new"]))
        XCTAssertFalse(CategoryInferenceService(overridesURL: categoriesURL).setOverride(.visual, for: "a"))
        XCTAssertThrowsError(try VersionedJSONStore<[String]>(url: versionedURL, currentSchemaVersion: 1).save(["new"]))
        for url in [notesURL, urlsURL, categoriesURL, versionedURL] { XCTAssertEqual(try Data(contentsOf: url), corrupt) }
    }

    func testLogTailReadsOnlyRequestedBytes() throws {
        let log = root.appendingPathComponent("log")
        let handleData = Data(repeating: 65, count: 1_000_000) + Data("last line\n".utf8)
        try handleData.write(to: log)
        XCTAssertEqual(ScriptExtenderService.readLogTail(at: log, maxBytes: 10), "last line\n")
        XCTAssertNil(ScriptExtenderService.readLogTail(at: log, maxBytes: 0))
    }

    func testZipAndCompressedTarExtractionEnforceSmallLimit() throws {
        let source = root.appendingPathComponent("payload.txt")
        try Data(repeating: 65, count: 1_024).write(to: source)
        let zip = root.appendingPathComponent("mod.zip")
        try ArchiveService().createZip(at: zip, entries: [(source, "payload.txt")])
        let tar = root.appendingPathComponent("mod.tar.gz")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["czf", tar.path, "-C", root.path, "payload.txt"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        for archive in [zip, tar] {
            let destination = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            XCTAssertThrowsError(try ArchiveService(maximumExpandedBytes: 100).extract(archive: archive, to: destination))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent("payload.txt").path))
        }
        let destination = root.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try ArchiveService().extract(archive: tar, to: destination)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("payload.txt")), try Data(contentsOf: source))
    }

    func testTarRejectsSymlinksAndEntryCountLimit() throws {
        let target = root.appendingPathComponent("target")
        try Data("target".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: target)
        let tar = root.appendingPathComponent("links.tar")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["cf", tar.path, "-C", root.path, "link"]
        try process.run(); process.waitUntilExit()
        let destination = root.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        XCTAssertThrowsError(try ArchiveService().extract(archive: tar, to: destination))
        XCTAssertThrowsError(try ArchiveService(maximumEntries: 0).extract(archive: tar, to: destination))
        XCTAssertEqual(try String(contentsOf: target), "target")
    }
}

private final class FailingCommitFileManager: FileManager, @unchecked Sendable {
    let failingDestination: URL
    init(failingDestination: URL) { self.failingDestination = failingDestination; super.init() }
    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        if dstURL == failingDestination && srcURL.lastPathComponent.contains(".staged-") {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}
