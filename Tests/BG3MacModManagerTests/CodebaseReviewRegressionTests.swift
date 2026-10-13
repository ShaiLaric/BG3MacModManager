// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

// Regressions for data safety and correctness findings from the codebase review.
final class CodebaseReviewRegressionTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BG3Review-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    func testCaseOnlyProfileRenamePreservesProfile() throws {
        let service = ProfileService(profilesDirectory: root)
        let profile = try service.save(name: "Campaign", activeMods: [])
        let renamed = try service.rename(profile: profile, to: "campaign")
        XCTAssertEqual(try service.listProfiles().map(\.id), [renamed.id])
    }

    func testFreshBackupSurvivesRetentionDespiteOldSourceModificationDate() throws {
        let source = root.appendingPathComponent("modsettings.lsx")
        try Data("old settings".utf8).write(to: source)
        let old = Date(timeIntervalSinceNow: -60 * 86400)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: source.path)
        let service = BackupService(modSettingsURL: source, backupsDirectory: root.appendingPathComponent("Backups"))
        let backup = try service.backupModSettings()
        try service.pruneBackups(olderThanDays: 30)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.url.path))
    }

    func testFeasiblePinnedOrderIsFound() {
        let a = makeModInfo(uuid: "a")
        let c = makeModInfo(uuid: "c")
        let b = makeModInfo(uuid: "b", dependencies: [makeDependency(uuid: "c")])
        let pin = LoadOrderRule(kind: .pinPosition, sourceUUID: "b", position: 2)
        let result = LoadOrderSolver().solve(mods: [a, c, b], rules: [pin], mode: .dependenciesOnly)
        XCTAssertEqual(result, .ordered([c, b, a]))
    }

    func testLSFRejectsOutOfRangeAttributeNodeReference() throws {
        var data = try makeTestSaveMetadataLSF(gameID: "campaign", mods: [], order: [])
        let namesSize = Int(data.readUInt32(at: 16))
        let nodesSize = Int(data.readUInt32(at: 32))
        let referenceOffset = 64 + namesSize + nodesSize + 8
        var invalidReference: Int32 = 50_000
        let bytes = withUnsafeBytes(of: &invalidReference) { Data($0) }
        data.replaceSubrange(referenceOffset..<(referenceOffset + 4), with: bytes)
        XCTAssertThrowsError(try LarianSaveMetadataReader().read(data: data))
    }

    func testRollbackCopyFailureCleansStagedFile() throws {
        let source = root.appendingPathComponent("source.pak")
        let destination = root.appendingPathComponent("destination.pak")
        try Data("new".utf8).write(to: source)
        try Data("old".utf8).write(to: destination)
        XCTAssertThrowsError(try TransactionalFileService.replaceFiles([
            .init(source: source, destination: destination),
        ], fileManager: ReviewRollbackCopyFailure()))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.contains(".staged-") }
        XCTAssertTrue(leftovers.isEmpty, "Leaked files: \(leftovers)")
    }

    func testDirectPAKReplacementDropsStaleCompanionMetadata() throws {
        let mods = root.appendingPathComponent("Mods")
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        let uuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        let installed = mods.appendingPathComponent("Test.pak")
        try Data("old".utf8).write(to: installed)
        let json = #"{"mods":[{"UUID":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","Name":"Old","Folder":"Test","version":"1.0.0.0"}]}"#
        try Data(json.utf8).write(to: mods.appendingPathComponent("Test.json"))
        let candidate = root.appendingPathComponent("Test.pak")
        let xml = "<save><node id=\"ModuleInfo\"><attribute id=\"UUID\" value=\"\(uuid)\"/><attribute id=\"Name\" value=\"New\"/><attribute id=\"Folder\" value=\"Test\"/><attribute id=\"Version64\" value=\"\(Version64(major: 2).rawValue)\"/></node></save>"
        try makeUncompressedTestPak(entries: [("Mods/Test/meta.lsx", Data(xml.utf8))]).write(to: candidate)
        XCTAssertTrue(ModImportService(backupsDirectory: root.appendingPathComponent("ImportBackups")).importMods(from: [candidate], to: mods).errors.isEmpty)
        let discovered = try XCTUnwrap(ModDiscoveryService(modsFolder: mods).discoverMods().first)
        XCTAssertEqual(discovered.version64, Version64(major: 2).rawValue)
        XCTAssertEqual(discovered.name, "New")
    }

    func testRestoreFailureLeavesInstalledVersionIntact() async throws {
        let mods = root.appendingPathComponent("Mods")
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        let installed = try writePAK(to: mods.appendingPathComponent("Test.pak"), version: 1)
        let candidate = try writePAK(to: root.appendingPathComponent("Test.pak"), version: 2)
        let json = #"{"mods":[{"UUID":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","Name":"Test","Folder":"Test","version":"2.0.0.0"}]}"#
        try Data(json.utf8).write(to: root.appendingPathComponent("Test.json"))
        let fm = ReviewRemoveFailure()
        let history = root.appendingPathComponent("history.json")
        let service = ModUpdateService(modsFolder: mods, backupsDirectory: root.appendingPathComponent("Backups"), historyURL: history, fileManager: fm)
        let plan = try await service.inspect(sourceURL: candidate, target: target(installed), wasActive: true, previousUserPosition: 1, nexusURL: nil)
        let record = try await service.execute(plan) { _ in }
        let installedVersion = try Data(contentsOf: installed)
        fm.failureURL = mods.appendingPathComponent("Test.json")
        do {
            _ = try await service.restore(record) { _ in }
            XCTFail("Expected simulated companion deletion failure")
        } catch {
            XCTAssertEqual(try Data(contentsOf: installed), installedVersion, "Restore failed after replacing the PAK, leaving history and companion metadata on the new version")
        }
    }

    func testRestoreRejectsDamagedBackupBeforeChangingInstalledFiles() async throws {
        let mods = root.appendingPathComponent("Mods")
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        let installed = try writePAK(to: mods.appendingPathComponent("Test.pak"), version: 1)
        let candidate = try writePAK(to: root.appendingPathComponent("Test.pak"), version: 2)
        let backups = root.appendingPathComponent("Backups")
        let service = ModUpdateService(modsFolder: mods, backupsDirectory: backups, historyURL: root.appendingPathComponent("history.json"))
        let plan = try await service.inspect(sourceURL: candidate, target: target(installed), wasActive: true, previousUserPosition: 1, nexusURL: nil)
        let record = try await service.execute(plan) { _ in }
        let updated = try Data(contentsOf: installed)
        let backup = backups.appendingPathComponent(record.backupDirectoryName).appendingPathComponent("Test.pak")
        try Data("damaged backup".utf8).write(to: backup)
        do {
            _ = try await service.restore(record) { _ in }
            XCTFail("Expected backup integrity failure")
        } catch {
            XCTAssertEqual(try Data(contentsOf: installed), updated)
        }
    }

    func testRestoreHistoryFailureRollsBackPAKAndCompanionDeletion() async throws {
        let mods = root.appendingPathComponent("Mods")
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        let installed = try writePAK(to: mods.appendingPathComponent("Test.pak"), version: 1)
        let candidate = try writePAK(to: root.appendingPathComponent("Test.pak"), version: 2)
        let json = Data(#"{"mods":[{"UUID":"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa","Name":"Test","Folder":"Test","version":"2.0.0.0"}]}"#.utf8)
        try json.write(to: root.appendingPathComponent("Test.json"))
        let history = root.appendingPathComponent("history.json")
        let service = ModUpdateService(modsFolder: mods, backupsDirectory: root.appendingPathComponent("Backups"), historyURL: history)
        let plan = try await service.inspect(sourceURL: candidate, target: target(installed), wasActive: true, previousUserPosition: 1, nexusURL: nil)
        let record = try await service.execute(plan) { _ in }
        let updated = try Data(contentsOf: installed)
        do {
            _ = try await service.restore(record) { progress in
                if progress.stage == .restoring {
                    try? Data("unreadable history".utf8).write(to: history, options: .atomic)
                }
            }
            XCTFail("Expected history persistence failure")
        } catch {
            XCTAssertEqual(try Data(contentsOf: installed), updated)
            XCTAssertEqual(try Data(contentsOf: mods.appendingPathComponent("Test.json")), json)
        }
    }

    func testOrdinaryImportRetainsDurableOriginalAndReplacesCompanion() throws {
        let mods = root.appendingPathComponent("Mods")
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        let installed = try writePAK(to: mods.appendingPathComponent("Test.pak"), version: 1)
        let old = try Data(contentsOf: installed)
        let candidate = try writePAK(to: root.appendingPathComponent("Test.pak"), version: 2)
        let oldJSON = Data("{\"old\":true}".utf8)
        let newJSON = Data("{\"new\":true}".utf8)
        try oldJSON.write(to: mods.appendingPathComponent("Test.json"))
        try newJSON.write(to: root.appendingPathComponent("Test.json"))
        let backups = root.appendingPathComponent("ImportBackups")
        let result = ModImportService(backupsDirectory: backups).importMods(from: [candidate], to: mods)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.replacedFilenames, ["Test.pak"])
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: backups, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Test.pak")), old)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Test.json")), oldJSON)
        XCTAssertEqual(try Data(contentsOf: mods.appendingPathComponent("Test.json")), newJSON)
    }

    func testCorruptNotesArePreservedBeforeEditing() throws {
        let notesURL = root.appendingPathComponent("notes.json")
        let corrupt = Data("{partially recoverable notes".utf8)
        try corrupt.write(to: notesURL)
        let service = ModNotesService(storageURL: notesURL)
        _ = service.setNote("new", for: "a")
        XCTAssertEqual(try Data(contentsOf: notesURL), corrupt, "A failed load must block writes or preserve the original")
    }

    func testWindowsCSVLineEndingsProduceSeparateRecords() {
        let csv = "name,url\r\nOne,https://www.nexusmods.com/baldursgate3/mods/1\r\nTwo,https://www.nexusmods.com/baldursgate3/mods/2\r\n"
        XCTAssertEqual(NexusURLImportService().parseCSVContent(csv, separator: ",").count, 2)
    }

    func testInvalidPAKImportPreservesExistingMod() throws {
        let mods = root.appendingPathComponent("Mods")
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
        let installed = try writePAK(to: mods.appendingPathComponent("Test.pak"), version: 1)
        let original = try Data(contentsOf: installed)
        let badDownload = root.appendingPathComponent("Test.pak")
        try Data("incomplete download".utf8).write(to: badDownload)
        let result = ModImportService(backupsDirectory: root.appendingPathComponent("ImportBackups")).importMods(from: [badDownload], to: mods)
        XCTAssertFalse(result.errors.isEmpty)
        XCTAssertEqual(try Data(contentsOf: installed), original)
    }

    private func target(_ url: URL) -> ModInfo {
        makeModInfo(uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", name: "Test", version64: Version64(major: 1).rawValue, pakFilePath: url)
    }

    private func writePAK(to url: URL, version: Int) throws -> URL {
        let xml = "<save><node id=\"ModuleInfo\"><attribute id=\"UUID\" value=\"aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa\"/><attribute id=\"Name\" value=\"Test\"/><attribute id=\"Folder\" value=\"Test\"/><attribute id=\"Version64\" value=\"\(Version64(major: version).rawValue)\"/></node></save>"
        try makeUncompressedTestPak(entries: [("Mods/Test/meta.lsx", Data(xml.utf8))]).write(to: url)
        return url
    }
}

private final class ReviewRollbackCopyFailure: FileManager, @unchecked Sendable {
    override func copyItem(at srcURL: URL, to dstURL: URL) throws {
        if dstURL.lastPathComponent.contains(".rollback-") {
            throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
        }
        try super.copyItem(at: srcURL, to: dstURL)
    }
}

private final class ReviewRemoveFailure: FileManager, @unchecked Sendable {
    var failureURL: URL?
    override func removeItem(at url: URL) throws {
        if url == failureURL { throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteNoPermissionError) }
        try super.removeItem(at: url)
    }
}
