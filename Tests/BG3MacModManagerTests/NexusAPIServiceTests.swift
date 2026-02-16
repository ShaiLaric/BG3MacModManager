// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class NexusAPIServiceTests: XCTestCase {

    var service: NexusAPIService!

    override func setUp() {
        super.setUp()
        service = NexusAPIService()
    }

    // MARK: - Extract Mod ID

    func testExtractModIDFromStandardURL() {
        XCTAssertEqual(
            service.extractModID(from: "https://www.nexusmods.com/baldursgate3/mods/12345"),
            12345
        )
    }

    func testExtractModIDFromURLWithTab() {
        XCTAssertEqual(
            service.extractModID(from: "https://www.nexusmods.com/baldursgate3/mods/9999?tab=files"),
            9999
        )
    }

    func testExtractModIDFromURLWithTrailingSlash() {
        XCTAssertEqual(
            service.extractModID(from: "https://www.nexusmods.com/baldursgate3/mods/42/"),
            42
        )
    }

    func testExtractModIDFromInvalidURL() {
        XCTAssertNil(service.extractModID(from: "https://www.google.com"))
    }

    func testExtractModIDFromEmptyString() {
        XCTAssertNil(service.extractModID(from: ""))
    }

    func testExtractModIDFromURLWithoutNumber() {
        XCTAssertNil(service.extractModID(from: "https://www.nexusmods.com/baldursgate3/mods/"))
    }

    // MARK: - NexusUpdateResult.hasUpdate

    func testHasUpdateWhenVersionsDiffer() {
        let result = NexusUpdateResult(
            modUUID: "test", nexusModID: 1,
            installedVersion: "1.0.0", latestVersion: "1.1.0",
            latestName: "Test Mod", updatedDate: nil,
            nexusURL: "https://www.nexusmods.com/baldursgate3/mods/1",
            checkedDate: Date()
        )
        XCTAssertTrue(result.hasUpdate)
    }

    func testNoUpdateWhenVersionsMatch() {
        let result = NexusUpdateResult(
            modUUID: "test", nexusModID: 1,
            installedVersion: "1.0.0", latestVersion: "1.0.0",
            latestName: "Test Mod", updatedDate: nil,
            nexusURL: "https://www.nexusmods.com/baldursgate3/mods/1",
            checkedDate: Date()
        )
        XCTAssertFalse(result.hasUpdate)
    }

    func testCaseInsensitiveVersionMatch() {
        let result = NexusUpdateResult(
            modUUID: "test", nexusModID: 1,
            installedVersion: "V1.0", latestVersion: "v1.0",
            latestName: "Test Mod", updatedDate: nil,
            nexusURL: "https://www.nexusmods.com/baldursgate3/mods/1",
            checkedDate: Date()
        )
        XCTAssertFalse(result.hasUpdate)
    }

    func testNoUpdateWhenLatestVersionEmpty() {
        let result = NexusUpdateResult(
            modUUID: "test", nexusModID: 1,
            installedVersion: "1.0.0", latestVersion: "",
            latestName: "Test Mod", updatedDate: nil,
            nexusURL: "https://www.nexusmods.com/baldursgate3/mods/1",
            checkedDate: Date()
        )
        XCTAssertFalse(result.hasUpdate)
    }

    func testHasUpdateWithFreeFormVersionStrings() {
        let result = NexusUpdateResult(
            modUUID: "test", nexusModID: 1,
            installedVersion: "Release 4", latestVersion: "Release 5",
            latestName: "Test Mod", updatedDate: nil,
            nexusURL: "https://www.nexusmods.com/baldursgate3/mods/1",
            checkedDate: Date()
        )
        XCTAssertTrue(result.hasUpdate)
    }

    // MARK: - NexusUpdateCache Codable

    func testNexusUpdateCacheRoundTrip() throws {
        let result = NexusUpdateResult(
            modUUID: "test-uuid", nexusModID: 42,
            installedVersion: "1.0", latestVersion: "2.0",
            latestName: "Test", updatedDate: Date(timeIntervalSince1970: 1700000000),
            nexusURL: "https://www.nexusmods.com/baldursgate3/mods/42",
            checkedDate: Date(timeIntervalSince1970: 1700001000)
        )
        var cache = NexusUpdateCache()
        cache.results["test-uuid"] = result
        cache.lastFullCheck = Date(timeIntervalSince1970: 1700001000)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(cache)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(NexusUpdateCache.self, from: data)

        XCTAssertEqual(decoded.results.count, 1)
        XCTAssertEqual(decoded.results["test-uuid"]?.latestVersion, "2.0")
        XCTAssertNotNil(decoded.lastFullCheck)
    }
}
