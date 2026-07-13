// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import BG3MacModManager

final class SaveProfileAssociationServiceTests: XCTestCase {
    func testIndividualSaveOverridesCampaignAssociationAndPersists() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bg3mm-associations-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let service = SaveProfileAssociationService(url: url)
        let save = makeSave()
        let campaignProfile = UUID()
        let saveProfile = UUID()

        var associations = service.upserting(
            kind: .campaign, save: save, profileID: campaignProfile, in: []
        )
        associations = service.upserting(
            kind: .save, save: save, profileID: saveProfile, in: associations
        )
        try service.saveAssociations(associations)
        let loaded = try service.loadAssociations()

        let resolved = try XCTUnwrap(service.resolvedAssociation(for: save, in: loaded))
        XCTAssertEqual(resolved.matchedKind, .save)
        XCTAssertEqual(resolved.association.profileID, saveProfile)
        XCTAssertEqual(loaded.count, 2)
    }

    func testUpdatingAssociationRetainsIdentityAndCreationDate() {
        let service = SaveProfileAssociationService(
            url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let save = makeSave()
        let firstDate = Date(timeIntervalSince1970: 10)
        let first = service.upserting(
            kind: .campaign,
            save: save,
            profileID: UUID(),
            in: [],
            now: firstDate
        )
        let replacementProfile = UUID()
        let second = service.upserting(
            kind: .campaign,
            save: save,
            profileID: replacementProfile,
            in: first,
            now: Date(timeIntervalSince1970: 20)
        )

        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].id, first[0].id)
        XCTAssertEqual(second[0].createdAt, firstDate)
        XCTAssertEqual(second[0].profileID, replacementProfile)
    }

    func testMissingProfileDoesNotRedirectAssociation() {
        let service = SaveProfileAssociationService(
            url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        )
        let save = makeSave()
        let deletedProfileID = UUID()
        let associations = service.upserting(
            kind: .save, save: save, profileID: deletedProfileID, in: []
        )

        XCTAssertEqual(
            service.resolvedAssociation(for: save, in: associations)?.association.profileID,
            deletedProfileID
        )
    }

    private func makeSave() -> SaveGameSummary {
        SaveGameSummary(
            id: "save-id",
            campaignID: "campaign-id",
            campaignName: "Campaign",
            displayName: "QuickSave",
            relativePath: "Campaign/QuickSave.lsv",
            fileURL: URL(fileURLWithPath: "/tmp/QuickSave.lsv"),
            screenshotURL: nil,
            modifiedAt: Date(timeIntervalSince1970: 1),
            fileSize: 100,
            fileResourceIdentity: nil,
            mods: [],
            modListFingerprint: "fingerprint",
            readError: nil
        )
    }
}
