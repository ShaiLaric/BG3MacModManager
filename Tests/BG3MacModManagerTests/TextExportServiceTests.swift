// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class TextExportServiceTests: XCTestCase {

    var service: TextExportService!

    override func setUp() {
        super.setUp()
        service = TextExportService()
    }

    // MARK: - Test Data

    private func sampleMods() -> [ModInfo] {
        [
            makeModInfo(uuid: "aaa", name: "Alpha Mod", author: "Alice", tags: ["gameplay"]),
            makeModInfo(uuid: "bbb", name: "Beta Mod", author: "Bob", tags: ["visual"], requiresScriptExtender: true),
        ]
    }

    // MARK: - CSV Format

    func testCSVHeaderRow() {
        let output = service.export(activeMods: sampleMods(), format: .csv)
        let firstLine = output.components(separatedBy: "\r\n").first!
        XCTAssertTrue(firstLine.contains("Position"))
        XCTAssertTrue(firstLine.contains("Name"))
        XCTAssertTrue(firstLine.contains("Author"))
        XCTAssertTrue(firstLine.contains("UUID"))
        XCTAssertTrue(firstLine.contains("Version"))
        XCTAssertTrue(firstLine.contains("PAK File"))
    }

    func testCSVRowCount() {
        let mods = sampleMods()
        let output = service.export(activeMods: mods, format: .csv)
        let lines = output.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        // 1 header + N data rows
        XCTAssertEqual(lines.count, mods.count + 1)
    }

    func testCSVContainsModNames() {
        let output = service.export(activeMods: sampleMods(), format: .csv)
        XCTAssertTrue(output.contains("Alpha Mod"))
        XCTAssertTrue(output.contains("Beta Mod"))
    }

    func testCSVEscapesCommas() {
        let mods = [makeModInfo(name: "Mod, With Comma", author: "Auth")]
        let output = service.export(activeMods: mods, format: .csv)
        XCTAssertTrue(output.contains("\"Mod, With Comma\""))
    }

    func testCSVEscapesDoubleQuotes() {
        let mods = [makeModInfo(name: "Mod \"Quoted\"", author: "Auth")]
        let output = service.export(activeMods: mods, format: .csv)
        XCTAssertTrue(output.contains("\"Mod \"\"Quoted\"\"\""))
    }

    func testCSVEmptyModList() {
        let output = service.export(activeMods: [], format: .csv)
        let lines = output.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        XCTAssertEqual(lines.count, 1) // Header only
    }

    func testCSVLineEndingsAreCRLF() {
        let output = service.export(activeMods: sampleMods(), format: .csv)
        // Should contain \r\n and end with \r\n
        XCTAssertTrue(output.contains("\r\n"))
        XCTAssertTrue(output.hasSuffix("\r\n"))
    }

    func testCSVPositionNumbers() {
        let output = service.export(activeMods: sampleMods(), format: .csv)
        let lines = output.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        // Data rows start with position number
        XCTAssertTrue(lines[1].hasPrefix("1,"))
        XCTAssertTrue(lines[2].hasPrefix("2,"))
    }

    // MARK: - Markdown Format

    func testMarkdownHeader() {
        let output = service.export(activeMods: sampleMods(), format: .markdown)
        XCTAssertTrue(output.hasPrefix("# Mod Load Order"))
    }

    func testMarkdownTableStructure() {
        let output = service.export(activeMods: sampleMods(), format: .markdown)
        let lines = output.components(separatedBy: "\n")
        // Should have header row with pipes and separator row
        let headerLine = lines.first { $0.contains("| # |") }
        XCTAssertNotNil(headerLine)
        let separatorLine = lines.first { $0.contains("|---|") }
        XCTAssertNotNil(separatorLine)
    }

    func testMarkdownContainsModNames() {
        let output = service.export(activeMods: sampleMods(), format: .markdown)
        XCTAssertTrue(output.contains("Alpha Mod"))
        XCTAssertTrue(output.contains("Beta Mod"))
    }

    func testMarkdownPipeEscaping() {
        let mods = [makeModInfo(name: "Mod|With|Pipes", author: "Auth")]
        let output = service.export(activeMods: mods, format: .markdown)
        XCTAssertTrue(output.contains("Mod\\|With\\|Pipes"))
    }

    func testMarkdownTotalLine() {
        let mods = sampleMods()
        let output = service.export(activeMods: mods, format: .markdown)
        XCTAssertTrue(output.contains("**Total:** \(mods.count) active mods"))
    }

    func testMarkdownTotalLineSingular() {
        let mods = [makeModInfo(name: "Only Mod")]
        let output = service.export(activeMods: mods, format: .markdown)
        XCTAssertTrue(output.contains("**Total:** 1 active mod"))
        // Should NOT have "mods" (plural)
        XCTAssertFalse(output.contains("1 active mods"))
    }

    // MARK: - Plain Text Format

    func testPlainTextNumberedList() {
        let output = service.export(activeMods: sampleMods(), format: .plainText)
        XCTAssertTrue(output.contains("1. Alpha Mod"))
        XCTAssertTrue(output.contains("2. Beta Mod"))
    }

    func testPlainTextContainsVersionAndAuthor() {
        let output = service.export(activeMods: sampleMods(), format: .plainText)
        XCTAssertTrue(output.contains("by Alice"))
        XCTAssertTrue(output.contains("by Bob"))
    }

    func testPlainTextContainsUUID() {
        let output = service.export(activeMods: sampleMods(), format: .plainText)
        XCTAssertTrue(output.contains("UUID: aaa"))
        XCTAssertTrue(output.contains("UUID: bbb"))
    }

    func testPlainTextTotalLine() {
        let mods = sampleMods()
        let output = service.export(activeMods: mods, format: .plainText)
        XCTAssertTrue(output.contains("Total: \(mods.count) active mods"))
    }

    func testPlainTextRequiresSEIndicator() {
        let output = service.export(activeMods: sampleMods(), format: .plainText)
        XCTAssertTrue(output.contains("Requires SE"))
    }

    // MARK: - ExportFormat Properties

    func testExportFormatFileExtensions() {
        XCTAssertEqual(TextExportService.ExportFormat.csv.fileExtension, "csv")
        XCTAssertEqual(TextExportService.ExportFormat.markdown.fileExtension, "md")
        XCTAssertEqual(TextExportService.ExportFormat.plainText.fileExtension, "txt")
    }
}
