// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import BG3MacModManager

final class SaveProfileComparatorTests: XCTestCase {
    private let uuidA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
    private let uuidB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
    private let uuidC = "cccccccc-cccc-cccc-cccc-cccccccccccc"

    func testDetectsMissingExtraVersionAndOrderDifferences() {
        let installedURL = URL(fileURLWithPath: "/tmp/installed.pak")
        let expectedA = makeModInfo(uuid: uuidA, name: "A", version64: 1, pakFilePath: installedURL)
        let expectedB = makeModInfo(uuid: uuidB, name: "B", version64: 2, pakFilePath: installedURL)
        let profile = ModProfile(
            name: "Expected",
            activeModUUIDs: [uuidA, uuidB],
            mods: [ModProfileEntry(from: expectedA), ModProfileEntry(from: expectedB)]
        )
        let installedA = makeModInfo(uuid: uuidA, name: "A", version64: 3, pakFilePath: installedURL)
        let missingB = makeModInfo(uuid: uuidB, name: "B", version64: 2, pakFilePath: nil)
        let extra = makeModInfo(uuid: uuidC, name: "C", pakFilePath: installedURL)
        let save = makeSave(mods: [uuidA, uuidB])

        let result = SaveProfileComparator().compare(
            save: save,
            profile: profile,
            activeMods: [extra, missingB, installedA],
            installedMods: [installedA, missingB, extra]
        )

        XCTAssertEqual(result.missingInstalledUUIDs, [uuidB])
        XCTAssertEqual(result.extraActiveUUIDs, [uuidC])
        XCTAssertEqual(result.versionDifferences.map(\.uuid), [uuidA])
        XCTAssertTrue(result.currentOrderDiffers)
        XCTAssertFalse(result.saveOrderDiffersFromProfile)
        XCTAssertTrue(result.hasCurrentMismatch)
    }

    func testMatchingConfigurationHasNoMismatch() {
        let installedURL = URL(fileURLWithPath: "/tmp/installed.pak")
        let a = makeModInfo(uuid: uuidA, name: "A", version64: 1, pakFilePath: installedURL)
        let b = makeModInfo(uuid: uuidB, name: "B", version64: 2, pakFilePath: installedURL)
        let profile = ModProfile(
            name: "Expected",
            activeModUUIDs: [uuidA, uuidB],
            mods: [ModProfileEntry(from: a), ModProfileEntry(from: b)]
        )

        let result = SaveProfileComparator().compare(
            save: makeSave(mods: [uuidA, uuidB]),
            profile: profile,
            activeMods: [a, b],
            installedMods: [a, b]
        )

        XCTAssertFalse(result.hasCurrentMismatch)
        XCTAssertFalse(result.saveOrderDiffersFromProfile)
    }

    private func makeSave(mods: [String]) -> SaveGameSummary {
        SaveGameSummary(
            id: "save",
            campaignID: "campaign",
            campaignName: "Campaign",
            displayName: "Save",
            relativePath: "Save.lsv",
            fileURL: URL(fileURLWithPath: "/tmp/Save.lsv"),
            screenshotURL: nil,
            modifiedAt: Date(),
            fileSize: 1,
            fileResourceIdentity: nil,
            mods: mods.map { SaveModEntry(uuid: $0, name: $0, folder: $0, version64: 1, md5: "") },
            modListFingerprint: "fingerprint",
            readError: nil
        )
    }
}
