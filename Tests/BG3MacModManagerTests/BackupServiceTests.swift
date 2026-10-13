// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import XCTest
@testable import BG3MacModManager

final class BackupServiceTests: XCTestCase {
    private var root: URL!
    private var settings: URL!
    private var backups: URL!
    private var service: BackupService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupServiceTests-\(UUID().uuidString)")
        settings = root.appendingPathComponent("modsettings.lsx")
        backups = root.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try Data("live settings".utf8).write(to: settings)
        service = BackupService(modSettingsURL: settings, backupsDirectory: backups)
    }

    override func tearDownWithError() throws {
        // Clear test-created locks even when an assertion fails, without following symlinks.
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            _ = lchflags(url.path, 0)
        }
        try FileManager.default.removeItem(at: root)
    }

    func testNewBackupClearsInheritedLockAndPreservesLiveFileLock() throws {
        XCTAssertTrue(service.lockModSettings())

        let backup = try service.backupModSettings()

        XCTAssertFalse(try isLocked(backup.url))
        XCTAssertTrue(service.isModSettingsLocked())
        XCTAssertEqual(try Data(contentsOf: backup.url), try Data(contentsOf: settings))
        try service.delete(backup: backup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.url.path))
        XCTAssertTrue(service.isModSettingsLocked())
    }

    func testDeleteUnlocksLegacyBackup() throws {
        let legacy = try makeBackup(name: "modsettings-2026-02-13T03-31-27Z.lsx", daysOld: 60)
        XCTAssertTrue(try isLocked(legacy.url))

        try service.delete(backup: legacy)

        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.url.path))
        XCTAssertEqual(try String(contentsOf: settings), "live settings")
    }

    func testPruningDeletesExpiredLockedBackupAndKeepsRecentBackup() throws {
        let expired = try makeBackup(name: "expired.lsx", daysOld: 60)
        let recent = try makeBackup(name: "recent.lsx", daysOld: 1)

        try service.pruneBackups(olderThanDays: 30)

        XCTAssertFalse(FileManager.default.fileExists(atPath: expired.url.path))
        XCTAssertTrue(try isLocked(recent.url))
    }

    func testPruningReportsDeletionFailure() throws {
        let expired = try makeBackup(name: "expired.lsx", daysOld: 60)
        // An immutable directory permits reads but prevents removal of its children.
        XCTAssertEqual(lchflags(backups.path, UInt32(UF_IMMUTABLE)), 0)
        defer { _ = lchflags(backups.path, 0) }

        XCTAssertThrowsError(try service.pruneBackups(olderThanDays: 30))
        XCTAssertTrue(FileManager.default.fileExists(atPath: expired.url.path))
    }

    func testDeletingSymlinkDoesNotUnlockItsTarget() throws {
        XCTAssertTrue(service.lockModSettings())
        let link = backups.appendingPathComponent("link.lsx")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: settings)
        let backup = BackupService.Backup(id: "link", url: link, date: Date(), fileSize: 0)

        try service.delete(backup: backup)

        XCTAssertTrue(service.isModSettingsLocked())
        XCTAssertEqual(try String(contentsOf: settings), "live settings")
        XCTAssertFalse(FileManager.default.fileExists(atPath: link.path))
    }

    func testRestoreCreatesUnlockedSafetyBackupAndRelocksLiveSettings() throws {
        let original = try makeBackup(name: "original.lsx", daysOld: 60)
        // New backups are unlocked; legacy locked-backup deletion is covered separately.
        XCTAssertEqual(lchflags(original.url.path, 0), 0)
        XCTAssertTrue(service.lockModSettings())

        try service.restore(backup: original)

        XCTAssertTrue(service.isModSettingsLocked())
        XCTAssertEqual(try String(contentsOf: settings), "backup settings")
        let safety = try XCTUnwrap(service.listBackups().first {
            $0.url.lastPathComponent.hasPrefix("pre-restore-")
        })
        XCTAssertFalse(try isLocked(safety.url))
        XCTAssertEqual(try String(contentsOf: safety.url), "live settings")
    }

    private func makeBackup(name: String, daysOld: Int) throws -> BackupService.Backup {
        let url = backups.appendingPathComponent(name)
        try Data("backup settings".utf8).write(to: url)
        let date = Calendar.current.date(byAdding: .day, value: -daysOld, to: Date())!
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        XCTAssertEqual(lchflags(url.path, UInt32(UF_IMMUTABLE)), 0)
        return BackupService.Backup(id: name, url: url, date: date, fileSize: 15)
    }

    private func isLocked(_ url: URL) throws -> Bool {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        return info.st_flags & UInt32(UF_IMMUTABLE) != 0
    }
}
