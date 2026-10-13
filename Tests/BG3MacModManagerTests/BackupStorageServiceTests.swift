// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class BackupStorageServiceTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("BG3Storage-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    func testAccountingAndCleanupRetainActiveAndRecentCopies() throws {
        let activeID = UUID().uuidString
        let restoredID = UUID().uuidString
        let active = try directory("ModUpdateBackups/" + activeID, daysOld: 60)
        let restored = try directory("ModUpdateBackups/" + restoredID, daysOld: 60)
        let orphan = try directory("ModUpdateBackups/" + UUID().uuidString, daysOld: 60)
        let expiredImport = try directory("ImportBackups/" + UUID().uuidString, daysOld: 60)
        let recentImport = try directory("ImportBackups/" + UUID().uuidString, daysOld: 1)
        let settings = try directory("Backups", daysOld: 60)
        let history = ModUpdateHistoryService(url: root.appendingPathComponent("mod_update_history.json"))
        try history.save(.init(records: [record(activeID, status: .installed), record(restoredID, status: .restored)], provenanceByUUID: [:]))
        let service = BackupStorageService(appSupportDirectory: root)
        XCTAssertEqual(try service.usage().totalBytes, 6 * 16)
        try service.cleanExpiredRecoveryCopies(olderThanDays: 30)
        for url in [active, recentImport, settings] { XCTAssertTrue(FileManager.default.fileExists(atPath: url.path)) }
        for url in [restored, orphan, expiredImport] { XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
        XCTAssertEqual(try service.usage().totalBytes, 3 * 16)
    }

    func testUnreadableHistoryPreventsCleanup() throws {
        let backup = try directory("ModUpdateBackups/" + UUID().uuidString, daysOld: 60)
        try Data("damaged history".utf8).write(to: root.appendingPathComponent("mod_update_history.json"))
        XCTAssertThrowsError(try BackupStorageService(appSupportDirectory: root).cleanExpiredRecoveryCopies(olderThanDays: 30))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backup.path))
    }

    private func directory(_ name: String, daysOld: Int) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(repeating: 65, count: 16).write(to: url.appendingPathComponent("copy"))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -Double(daysOld) * 86_400)], ofItemAtPath: url.path)
        return url
    }
    private func record(_ directory: String, status: ModUpdateHistoryRecord.Status) -> ModUpdateHistoryRecord {
        .init(id: UUID(), modUUID: "a", modName: "Test", sourceArchiveName: "mod.pak", previousVersion64: 1, installedVersion64: 2, previousSHA256: "old", installedSHA256: "new", installedAt: Date(timeIntervalSinceNow: -60 * 86_400), status: status, restoredAt: Date(timeIntervalSinceNow: -60 * 86_400), backupDirectoryName: directory, backupItems: [], createdPaths: [], wasActive: false, previousUserPosition: nil, nexusURL: nil)
    }
}
