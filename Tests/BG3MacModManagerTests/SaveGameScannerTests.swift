// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import BG3MacModManager

final class SaveGameScannerTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bg3mm-save-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testScansSaveAndExtractsOrderedMods() async throws {
        let saveURL = try writeSave(
            folder: "Tavina-123456__QuickSave_1",
            name: "QuickSave_1",
            mods: [("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "First"),
                   ("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", "Second")]
        )

        let summaries = try await SaveGameScanner(storyDirectory: temporaryDirectory).scan()

        XCTAssertEqual(summaries.count, 1)
        XCTAssertEqual(summaries[0].campaignName, "Tavina")
        XCTAssertEqual(summaries[0].displayName, "QuickSave_1")
        XCTAssertEqual(summaries[0].mods.map(\.name), ["First", "Second"])
        XCTAssertEqual(summaries[0].fileURL.standardizedFileURL, saveURL.standardizedFileURL)
        XCTAssertNil(summaries[0].readError)
        XCTAssertNotNil(summaries[0].modListFingerprint)
    }

    func testCorruptSaveIsReportedInsteadOfTreatedAsEmpty() async throws {
        let folder = temporaryDirectory.appendingPathComponent("Tav-1__Broken", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not a pak".utf8).write(to: folder.appendingPathComponent("Broken.lsv"))

        let summaries = try await SaveGameScanner(storyDirectory: temporaryDirectory).scan()

        XCTAssertEqual(summaries.count, 1)
        XCTAssertFalse(summaries[0].isReadable)
        XCTAssertTrue(summaries[0].mods.isEmpty)
        XCTAssertNotNil(summaries[0].readError)
    }

    func testRenamePreservesSaveIdentityWhenResourceIdentityIsAvailable() async throws {
        let original = try writeSave(
            folder: "Tav-1__Original",
            name: "Original",
            mods: [("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "Mod")]
        )
        let scanner = SaveGameScanner(storyDirectory: temporaryDirectory)
        let originalResults = try await scanner.scan()
        let originalSummary = try XCTUnwrap(originalResults.first)

        let renamedFolder = temporaryDirectory.appendingPathComponent("Tav-2__Renamed", isDirectory: true)
        try FileManager.default.createDirectory(at: renamedFolder, withIntermediateDirectories: true)
        let renamed = renamedFolder.appendingPathComponent("Renamed.lsv")
        try FileManager.default.moveItem(at: original, to: renamed)
        let renamedResults = try await scanner.scan()
        let renamedSummary = try XCTUnwrap(renamedResults.first)

        if originalSummary.fileResourceIdentity != nil {
            XCTAssertEqual(renamedSummary.id, originalSummary.id)
        }
        XCTAssertEqual(renamedSummary.campaignID, originalSummary.campaignID)
    }

    func testChangedCorruptSaveIsRetried() async throws {
        let folder = temporaryDirectory.appendingPathComponent("Tav-1__Retry", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Retry.lsv")
        try Data("broken".utf8).write(to: url)
        let scanner = SaveGameScanner(storyDirectory: temporaryDirectory)
        let brokenResults = try await scanner.scan()
        XCTAssertNotNil(brokenResults.first?.readError)

        let settings = try modSettingsData(mods: [("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", "Fixed")])
        try makeUncompressedTestPak(entries: [("Save/modsettings.lsx", settings)]).write(to: url)
        let future = Date().addingTimeInterval(2)
        try FileManager.default.setAttributes([.modificationDate: future], ofItemAtPath: url.path)

        let repairedResults = try await scanner.scan()
        let summary = try XCTUnwrap(repairedResults.first)
        XCTAssertNil(summary.readError)
        XCTAssertEqual(summary.mods.map(\.name), ["Fixed"])
    }

    func testScansModernSaveMetadataAndUsesStableGameID() async throws {
        let mod = SaveModEntry(
            uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            name: "Modern Mod",
            folder: "ModernMod",
            version64: 123,
            md5: "abc"
        )
        let lsf = try makeTestSaveMetadataLSF(
            gameID: "logical-campaign-id",
            mods: [mod],
            order: [mod.uuid]
        )
        let firstFolder = temporaryDirectory.appendingPathComponent("FirstCharacter-1__Save", isDirectory: true)
        try FileManager.default.createDirectory(at: firstFolder, withIntermediateDirectories: true)
        let firstURL = firstFolder.appendingPathComponent("Modern.lsv")
        try makeUncompressedTestPak(entries: [("meta.lsf", lsf)]).write(to: firstURL)

        let secondFolder = temporaryDirectory.appendingPathComponent("RenamedCharacter-2__Save", isDirectory: true)
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        let secondURL = secondFolder.appendingPathComponent("Modern2.lsv")
        try makeUncompressedTestPak(entries: [("meta.lsf", lsf)]).write(to: secondURL)

        let summaries = try await SaveGameScanner(storyDirectory: temporaryDirectory).scan()

        XCTAssertEqual(summaries.count, 2)
        XCTAssertTrue(summaries.allSatisfy(\.isReadable))
        XCTAssertTrue(summaries.allSatisfy { $0.mods == [mod] })
        XCTAssertEqual(Set(summaries.map(\.campaignID)).count, 1)
    }

    private func writeSave(
        folder: String,
        name: String,
        mods: [(String, String)]
    ) throws -> URL {
        let directory = temporaryDirectory.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name).appendingPathExtension("lsv")
        let settings = try modSettingsData(mods: mods)
        try makeUncompressedTestPak(entries: [("Save/modsettings.lsx", settings)]).write(to: url)
        return url
    }

    private func modSettingsData(mods: [(String, String)]) throws -> Data {
        let url = temporaryDirectory.appendingPathComponent("settings-\(UUID().uuidString).lsx")
        var settings = ModSettingsService.ModSettings(modOrder: [], mods: [:])
        for (uuid, name) in mods {
            settings.modOrder.append(uuid)
            settings.mods[uuid] = .init(
                folder: name.replacingOccurrences(of: " ", with: ""),
                md5: "",
                name: name,
                uuid: uuid,
                version64: "36028797018963968"
            )
        }
        try ModSettingsService().write(settings, to: url)
        return try Data(contentsOf: url)
    }
}
