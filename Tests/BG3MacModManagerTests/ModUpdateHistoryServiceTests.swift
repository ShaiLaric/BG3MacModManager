// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import BG3MacModManager

final class ModUpdateHistoryServiceTests: XCTestCase {
    func testEmptyStoreAndRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bg3mm-update-history-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let service = ModUpdateHistoryService(url: url)
        XCTAssertTrue(try service.load().records.isEmpty)

        let record = ModUpdateHistoryRecord(
            id: UUID(),
            modUUID: "uuid",
            modName: "Mod",
            sourceArchiveName: "Update.zip",
            previousVersion64: 1,
            installedVersion64: 2,
            previousSHA256: "old",
            installedSHA256: "new",
            installedAt: Date(timeIntervalSince1970: 1),
            status: .installed,
            restoredAt: nil,
            backupDirectoryName: "backup",
            backupItems: [.init(originalPath: "/Mods/Mod.pak", backupRelativePath: "Mod.pak")],
            createdPaths: [],
            wasActive: true,
            previousUserPosition: 2,
            nexusURL: nil
        )
        let payload = ModUpdateHistoryPayload(records: [record], provenanceByUUID: [:])
        try service.save(payload)

        XCTAssertEqual(try service.load(), payload)
    }
}
