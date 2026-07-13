// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import BG3MacModManager

final class ModUpdateServiceTests: XCTestCase {
    private var root: URL!
    private var mods: URL!
    private var backups: URL!
    private var history: URL!
    private let targetUUID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("bg3mm-update-\(UUID().uuidString)", isDirectory: true)
        mods = root.appendingPathComponent("Mods", isDirectory: true)
        backups = root.appendingPathComponent("Backups", isDirectory: true)
        history = root.appendingPathComponent("history.json")
        try FileManager.default.createDirectory(at: mods, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testInspectRejectsMismatchedUUID() async throws {
        let installed = try writePAK(name: "Installed.pak", uuid: targetUUID, version: 1, marker: "old", to: mods)
        let candidate = try writePAK(
            name: "Candidate.pak",
            uuid: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            version: 2,
            marker: "new",
            to: root
        )
        let service = makeService()
        let target = makeModInfo(uuid: targetUUID, name: "Target", version64: 1, pakFilePath: installed)

        do {
            _ = try await service.inspect(
                sourceURL: candidate,
                target: target,
                wasActive: true,
                previousUserPosition: 3,
                nexusURL: nil
            )
            XCTFail("Expected UUID mismatch")
        } catch let error as ModUpdateService.UpdateError {
            guard case .UUIDMismatch(let expected, _) = error else {
                return XCTFail("Expected UUIDMismatch, got \(error)")
            }
            XCTAssertEqual(expected, targetUUID)
        }
        XCTAssertEqual(try marker(in: installed), "old")
    }

    func testInspectRejectsAmbiguousMultiPAKArchive() async throws {
        let installed = try writePAK(name: "Installed.pak", uuid: targetUUID, version: 1, marker: "old", to: mods)
        let first = try writePAK(name: "First.pak", uuid: targetUUID, version: 2, marker: "one", to: root)
        let second = try writePAK(
            name: "Second.pak",
            uuid: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            version: 1,
            marker: "two",
            to: root
        )
        let archive = root.appendingPathComponent("Update.zip")
        try ArchiveService().createZip(at: archive, entries: [
            (first, "First.pak"), (second, "Nested/Second.pak"),
        ])
        let target = makeModInfo(uuid: targetUUID, version64: 1, pakFilePath: installed)

        do {
            _ = try await makeService().inspect(
                sourceURL: archive,
                target: target,
                wasActive: false,
                previousUserPosition: nil,
                nexusURL: nil
            )
            XCTFail("Expected multi-PAK rejection")
        } catch let error as ModUpdateService.UpdateError {
            guard case .multiplePAKs(let names) = error else {
                return XCTFail("Expected multiplePAKs, got \(error)")
            }
            XCTAssertEqual(names, ["First.pak", "Second.pak"])
        }
    }

    func testExecuteRejectsInstalledPAKChangedAfterReview() async throws {
        let installed = try writePAK(name: "Installed.pak", uuid: targetUUID, version: 1, marker: "old", to: mods)
        let candidate = try writePAK(name: "Candidate.pak", uuid: targetUUID, version: 2, marker: "new", to: root)
        let target = makeModInfo(uuid: targetUUID, name: "Target", version64: 1, pakFilePath: installed)
        let service = makeService()
        let plan = try await service.inspect(
            sourceURL: candidate,
            target: target,
            wasActive: true,
            previousUserPosition: 1,
            nexusURL: nil
        )
        _ = try writePAK(name: "Installed.pak", uuid: targetUUID, version: 1, marker: "external", to: mods)

        do {
            _ = try await service.execute(plan) { _ in }
            XCTFail("Expected stale-plan rejection")
        } catch let error as ModUpdateService.UpdateError {
            guard case .installedChangedSinceInspection = error else {
                return XCTFail("Expected installedChangedSinceInspection, got \(error)")
            }
        }
        XCTAssertEqual(try marker(in: installed), "external")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.stagingDirectory.path))
    }

    func testExecuteRejectsCandidateChangedAfterReview() async throws {
        let installed = try writePAK(name: "Installed.pak", uuid: targetUUID, version: 1, marker: "old", to: mods)
        let candidate = try writePAK(name: "Candidate.pak", uuid: targetUUID, version: 2, marker: "new", to: root)
        let target = makeModInfo(uuid: targetUUID, name: "Target", version64: 1, pakFilePath: installed)
        let service = makeService()
        let plan = try await service.inspect(
            sourceURL: candidate,
            target: target,
            wasActive: true,
            previousUserPosition: 1,
            nexusURL: nil
        )
        try Data("tampered".utf8).write(to: plan.candidatePAK)

        do {
            _ = try await service.execute(plan) { _ in }
            XCTFail("Expected changed-candidate rejection")
        } catch let error as ModUpdateService.UpdateError {
            guard case .candidateChangedSinceInspection = error else {
                return XCTFail("Expected candidateChangedSinceInspection, got \(error)")
            }
        }
        XCTAssertEqual(try marker(in: installed), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.stagingDirectory.path))
    }

    func testExecuteBacksUpCommitsVerifiesAndPersistsHistory() async throws {
        let installed = try writePAK(name: "Installed.pak", uuid: targetUUID, version: 1, marker: "old", to: mods)
        let candidate = try writePAK(name: "Candidate.pak", uuid: targetUUID, version: 2, marker: "new", to: root)
        let target = makeModInfo(uuid: targetUUID, name: "Target", version64: 1, pakFilePath: installed)
        let service = makeService()
        let plan = try await service.inspect(
            sourceURL: candidate,
            target: target,
            wasActive: true,
            previousUserPosition: 4,
            nexusURL: "https://www.nexusmods.com/baldursgate3/mods/42"
        )

        let record = try await service.execute(plan) { _ in }

        XCTAssertEqual(try marker(in: installed), "new")
        XCTAssertEqual(record.previousVersion64, 1)
        XCTAssertEqual(record.installedVersion64, 2)
        XCTAssertEqual(record.previousUserPosition, 4)
        XCTAssertEqual(record.status, .installed)
        let payload = try ModUpdateHistoryService(url: history).load()
        XCTAssertEqual(payload.records.first, record)
        XCTAssertEqual(payload.provenanceByUUID[targetUUID]?.nexusModID, 42)
        let backupPAK = backups
            .appendingPathComponent(record.backupDirectoryName)
            .appendingPathComponent("Installed.pak")
        XCTAssertEqual(try marker(in: backupPAK), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.stagingDirectory.path))
    }

    func testRestorePreviousVersionUsesDurableBackup() async throws {
        let installed = try writePAK(name: "Installed.pak", uuid: targetUUID, version: 1, marker: "old", to: mods)
        let candidate = try writePAK(name: "Candidate.pak", uuid: targetUUID, version: 2, marker: "new", to: root)
        let candidateJSON = root.appendingPathComponent("Candidate.json")
        try Data("""
        {"mods":[{"modName":"Target","folderName":"Target","UUID":"\(targetUUID)","version":"0.0.0.2"}]}
        """.utf8).write(to: candidateJSON)
        let target = makeModInfo(uuid: targetUUID, name: "Target", version64: 1, pakFilePath: installed)
        let service = makeService()
        let plan = try await service.inspect(
            sourceURL: candidate,
            target: target,
            wasActive: false,
            previousUserPosition: nil,
            nexusURL: nil
        )
        let record = try await service.execute(plan) { _ in }
        XCTAssertEqual(try marker(in: installed), "new")
        let installedJSON = mods.appendingPathComponent("Installed.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedJSON.path))

        let restored = try await service.restore(record) { _ in }

        XCTAssertEqual(try marker(in: installed), "old")
        XCTAssertFalse(FileManager.default.fileExists(atPath: installedJSON.path))
        XCTAssertEqual(restored.status, .restored)
        XCTAssertNotNil(restored.restoredAt)
        XCTAssertEqual(try ModUpdateHistoryService(url: history).load().records.first?.status, .restored)
    }

    func testRestoreRejectsInstalledPAKChangedAfterUpdate() async throws {
        let installed = try writePAK(name: "Installed.pak", uuid: targetUUID, version: 1, marker: "old", to: mods)
        let candidate = try writePAK(name: "Candidate.pak", uuid: targetUUID, version: 2, marker: "new", to: root)
        let target = makeModInfo(uuid: targetUUID, name: "Target", version64: 1, pakFilePath: installed)
        let service = makeService()
        let plan = try await service.inspect(
            sourceURL: candidate,
            target: target,
            wasActive: false,
            previousUserPosition: nil,
            nexusURL: nil
        )
        let record = try await service.execute(plan) { _ in }
        _ = try writePAK(name: "Installed.pak", uuid: targetUUID, version: 3, marker: "external", to: mods)

        do {
            _ = try await service.restore(record) { _ in }
            XCTFail("Expected changed-install rejection")
        } catch let error as ModUpdateService.UpdateError {
            guard case .installedChangedSinceUpdate = error else {
                return XCTFail("Expected installedChangedSinceUpdate, got \(error)")
            }
        }
        XCTAssertEqual(try marker(in: installed), "external")
        XCTAssertEqual(try ModUpdateHistoryService(url: history).load().records.first?.status, .installed)
    }

    func testRestoreRejectsHistoryPathsOutsideModsFolder() async {
        let record = ModUpdateHistoryRecord(
            id: UUID(),
            modUUID: targetUUID,
            modName: "Target",
            sourceArchiveName: "Candidate.pak",
            previousVersion64: 1,
            installedVersion64: 2,
            previousSHA256: "old",
            installedSHA256: "new",
            installedAt: Date(timeIntervalSince1970: 1),
            status: .installed,
            restoredAt: nil,
            backupDirectoryName: UUID().uuidString,
            backupItems: [.init(
                originalPath: "/tmp/outside-BG3-Mods.pak",
                backupRelativePath: "outside.pak"
            )],
            createdPaths: [],
            wasActive: false,
            previousUserPosition: nil,
            nexusURL: nil
        )
        try? ModUpdateHistoryService(url: history).save(.init(
            records: [record],
            provenanceByUUID: [:]
        ))

        do {
            _ = try await makeService().restore(record) { _ in }
            XCTFail("Expected unsafe history rejection")
        } catch let error as ModUpdateService.UpdateError {
            guard case .unsafeHistory = error else {
                return XCTFail("Expected unsafeHistory, got \(error)")
            }
        } catch {
            XCTFail("Expected UpdateError, got \(error)")
        }
    }

    private func makeService() -> ModUpdateService {
        ModUpdateService(modsFolder: mods, backupsDirectory: backups, historyURL: history)
    }

    private func writePAK(
        name: String,
        uuid: String,
        version: Int64,
        marker: String,
        to directory: URL
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let metadata = Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <save><region id="Config"><node id="root"><children>
        <node id="ModuleInfo">
          <attribute id="UUID" type="guid" value="\(uuid)"/>
          <attribute id="Folder" type="LSString" value="Target"/>
          <attribute id="Name" type="LSString" value="Target"/>
          <attribute id="Version64" type="int64" value="\(version)"/>
        </node>
        </children></node></region></save>
        """.utf8)
        let url = directory.appendingPathComponent(name)
        let data = makeUncompressedTestPak(entries: [
            ("Mods/Target/meta.lsx", metadata),
            ("Public/Target/marker.txt", Data(marker.utf8)),
        ])
        try data.write(to: url)
        return url
    }

    private func marker(in pak: URL) throws -> String {
        let data = try PakReader.extractFile(named: "Public/Target/marker.txt", from: pak)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
