// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class NexusURLImportServiceTests: XCTestCase {

    var service: NexusURLImportService!

    override func setUp() {
        super.setUp()
        service = NexusURLImportService()
    }

    // MARK: - Extract Mod ID

    func testExtractModIDFromStandardURL() {
        XCTAssertEqual(
            service.extractModID(from: "https://www.nexusmods.com/baldursgate3/mods/12345"),
            "12345"
        )
    }

    func testExtractModIDFromURLWithQueryParams() {
        XCTAssertEqual(
            service.extractModID(from: "https://www.nexusmods.com/baldursgate3/mods/9999?tab=files"),
            "9999"
        )
    }

    func testExtractModIDFromInvalidURL() {
        XCTAssertNil(service.extractModID(from: "https://www.google.com"))
    }

    func testExtractModIDFromEmptyString() {
        XCTAssertNil(service.extractModID(from: ""))
    }

    // MARK: - isNexusURL

    func testIsNexusURLValid() {
        XCTAssertTrue(service.isNexusURL("https://www.nexusmods.com/baldursgate3/mods/1"))
    }

    func testIsNexusURLInvalid() {
        XCTAssertFalse(service.isNexusURL("https://www.google.com"))
    }

    func testIsNexusURLCaseInsensitive() {
        XCTAssertTrue(service.isNexusURL("https://www.NexusMods.com/baldursgate3/mods/1"))
    }

    // MARK: - CSV Parsing

    func testParseCSVTwoColumns() {
        let csv = """
        ModA,https://www.nexusmods.com/baldursgate3/mods/111
        ModB,https://www.nexusmods.com/baldursgate3/mods/222
        """
        let entries = service.parseCSVContent(csv, separator: ",")
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].identifier, "ModA")
        XCTAssertEqual(entries[0].nexusURL, "https://www.nexusmods.com/baldursgate3/mods/111")
        XCTAssertEqual(entries[0].nexusModID, "111")
    }

    func testParseCSVSkipsHeader() {
        let csv = """
        Name,URL
        ModA,https://www.nexusmods.com/baldursgate3/mods/111
        """
        let entries = service.parseCSVContent(csv, separator: ",")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].identifier, "ModA")
    }

    func testParseCSVSingleColumnURLs() {
        let csv = """
        https://www.nexusmods.com/baldursgate3/mods/111
        https://www.nexusmods.com/baldursgate3/mods/222
        """
        let entries = service.parseCSVContent(csv, separator: ",")
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(entries[0].identifier.isEmpty)
    }

    func testParseCSVIgnoresNonNexusURLs() {
        let csv = """
        ModA,https://www.google.com
        ModB,https://www.nexusmods.com/baldursgate3/mods/222
        """
        let entries = service.parseCSVContent(csv, separator: ",")
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].identifier, "ModB")
    }

    // MARK: - JSON Parsing

    func testParseJSONArrayFormat() throws {
        let json = """
        [
            {"name": "ModA", "url": "https://www.nexusmods.com/baldursgate3/mods/111"},
            {"name": "ModB", "url": "https://www.nexusmods.com/baldursgate3/mods/222"}
        ]
        """
        let entries = try service.parseJSONContent(json)
        XCTAssertEqual(entries.count, 2)
    }

    func testParseJSONDictionaryFormat() throws {
        let json = """
        {
            "some-uuid": "https://www.nexusmods.com/baldursgate3/mods/111",
            "other-uuid": "https://www.nexusmods.com/baldursgate3/mods/222"
        }
        """
        let entries = try service.parseJSONContent(json)
        XCTAssertEqual(entries.count, 2)
    }

    func testParseJSONInvalidThrows() {
        XCTAssertThrowsError(try service.parseJSONContent("not json at all"))
    }

    func testParseJSONAlternativeKeys() throws {
        let json = """
        [{"modName": "ModA", "nexus_url": "https://www.nexusmods.com/baldursgate3/mods/111"}]
        """
        let entries = try service.parseJSONContent(json)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].identifier, "ModA")
    }

    // MARK: - Plain Text Parsing

    func testParsePlainText() {
        let text = """
        https://www.nexusmods.com/baldursgate3/mods/111
        not a url
        https://www.nexusmods.com/baldursgate3/mods/222
        """
        let entries = service.parsePlainTextContent(text)
        XCTAssertEqual(entries.count, 2)
    }

    // MARK: - Matching

    func testMatchByExactName() throws {
        let mods = [makeTestMod(uuid: "uuid-1", name: "Cool Mod")]
        let result = try service.parseAndMatch(
            content: "Cool Mod,https://www.nexusmods.com/baldursgate3/mods/111",
            format: .csv,
            installedMods: mods
        )
        XCTAssertEqual(result.matched.count, 1)
        XCTAssertEqual(result.matched[0].matchType, .exactName)
        XCTAssertEqual(result.matched[0].matchedMod.uuid, "uuid-1")
    }

    func testMatchByUUID() throws {
        let mods = [makeTestMod(uuid: "abc-123", name: "Cool Mod")]
        let result = try service.parseAndMatch(
            content: "abc-123,https://www.nexusmods.com/baldursgate3/mods/111",
            format: .csv,
            installedMods: mods
        )
        XCTAssertEqual(result.matched.count, 1)
        XCTAssertEqual(result.matched[0].matchType, .uuid)
    }

    func testMatchByFuzzyName() throws {
        let mods = [makeTestMod(uuid: "uuid-1", name: "Cool Mod Extended")]
        let result = try service.parseAndMatch(
            content: "Cool Mod,https://www.nexusmods.com/baldursgate3/mods/111",
            format: .csv,
            installedMods: mods
        )
        XCTAssertEqual(result.matched.count, 1)
        XCTAssertEqual(result.matched[0].matchType, .fuzzyName)
    }

    func testUnmatchedEntries() throws {
        let mods = [makeTestMod(uuid: "uuid-1", name: "Cool Mod")]
        let result = try service.parseAndMatch(
            content: "Unknown Mod,https://www.nexusmods.com/baldursgate3/mods/111",
            format: .csv,
            installedMods: mods
        )
        XCTAssertEqual(result.matched.count, 0)
        XCTAssertEqual(result.unmatched.count, 1)
    }

    func testNoValidEntriesThrows() {
        XCTAssertThrowsError(try service.parseAndMatch(
            content: "no nexus urls here",
            format: .text,
            installedMods: []
        ))
    }

    // MARK: - Helpers

    private func makeTestMod(uuid: String, name: String) -> ModInfo {
        makeModInfo(uuid: uuid, name: name)
    }
}
