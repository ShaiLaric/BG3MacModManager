// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import BG3MacModManager

final class NexusUpdatePreferenceServiceTests: XCTestCase {
    private var temporaryURLs: [URL] = []

    override func tearDown() {
        temporaryURLs.forEach { try? FileManager.default.removeItem(at: $0) }
        temporaryURLs.removeAll()
        super.tearDown()
    }

    func testIgnoredVersionSuppressesOnlyMatchingPageAndVersion() {
        let service = makeService()
        let result = makeResult(version: "2.0.0", modID: 42)
        let preferences = service.ignoring(
            result,
            in: [:],
            now: Date(timeIntervalSince1970: 100)
        )
        let preference = preferences[ModIdentity.comparisonKey(result.modUUID)]

        XCTAssertEqual(preference?.ignoredVersion, "2.0.0")
        XCTAssertTrue(preference?.suppresses(result) == true)
        XCTAssertTrue(preference?.suppresses(makeResult(version: "v2.0", modID: 42)) == true)
        XCTAssertFalse(preference?.suppresses(makeResult(version: "2.1.0", modID: 42)) == true)
        XCTAssertFalse(preference?.suppresses(makeResult(version: "2.0.0", modID: 99)) == true)
    }

    func testDisabledChecksSuppressEveryResult() {
        let service = makeService()
        let preferences = service.settingChecksDisabled(
            true,
            for: "Mixed-Case-UUID",
            in: [:],
            now: Date(timeIntervalSince1970: 100)
        )

        let preference = preferences["mixed-case-uuid"]
        XCTAssertTrue(preference?.checksDisabled == true)
        XCTAssertTrue(preference?.suppresses(makeResult(version: "99.0", modID: 99)) == true)
    }

    func testClearingIgnoredVersionRetainsDisabledPreference() {
        let service = makeService()
        let result = makeResult(version: "2.0.0", modID: 42)
        var preferences = service.ignoring(result, in: [:])
        preferences = service.settingChecksDisabled(true, for: result.modUUID, in: preferences)
        preferences = service.clearingIgnoredVersion(for: result.modUUID, in: preferences)

        let preference = preferences[ModIdentity.comparisonKey(result.modUUID)]
        XCTAssertNil(preference?.ignoredVersion)
        XCTAssertNil(preference?.ignoredNexusModID)
        XCTAssertTrue(preference?.checksDisabled == true)
    }

    func testPreferencesPersistWithNormalizedUUIDs() throws {
        let service = makeService()
        let preferences = service.settingChecksDisabled(
            true,
            for: "Mixed-Case-UUID",
            in: [:],
            now: Date(timeIntervalSince1970: 100)
        )

        try service.savePreferences(preferences)
        let loaded = try service.loadPreferences()

        XCTAssertEqual(loaded, preferences)
        XCTAssertNotNil(loaded["mixed-case-uuid"])
    }

    private func makeService() -> NexusUpdatePreferenceService {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bg3mm-nexus-preferences-\(UUID().uuidString)")
        temporaryURLs.append(directory)
        return NexusUpdatePreferenceService(url: directory.appendingPathComponent("preferences.json"))
    }

    private func makeResult(version: String, modID: Int) -> NexusUpdateResult {
        NexusUpdateResult(
            modUUID: "Mixed-Case-UUID",
            nexusModID: modID,
            installedVersion: "1.0.0",
            latestVersion: version,
            latestName: "Optional File",
            updatedDate: nil,
            nexusURL: "https://www.nexusmods.com/baldursgate3/mods/\(modID)",
            checkedDate: Date(timeIntervalSince1970: 100)
        )
    }
}
