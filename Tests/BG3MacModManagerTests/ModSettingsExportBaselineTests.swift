// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class ModSettingsExportBaselineTests: XCTestCase {

    private let defaultPath = "/Users/test/Documents/Larian Studios/Baldur's Gate 3/PlayerProfiles/Public/modsettings.lsx"
    private let movedPath = "/Volumes/Games/Baldur's Gate 3/PlayerProfiles/Public/modsettings.lsx"

    // MARK: - Parsing

    func testLegacyHashOnlyFileParsesWithoutPath() {
        let baseline = ModSettingsExportBaseline(fileContents: "abc123")
        XCTAssertEqual(baseline, ModSettingsExportBaseline(hash: "abc123", path: nil))
    }

    func testLegacyFileWithTrailingNewlineParsesWithoutPath() {
        let baseline = ModSettingsExportBaseline(fileContents: "abc123\n")
        XCTAssertEqual(baseline, ModSettingsExportBaseline(hash: "abc123", path: nil))
    }

    func testHashAndPathParse() {
        let baseline = ModSettingsExportBaseline(fileContents: "abc123\n\(movedPath)")
        XCTAssertEqual(baseline, ModSettingsExportBaseline(hash: "abc123", path: movedPath))
    }

    func testEmptyFileDoesNotParse() {
        XCTAssertNil(ModSettingsExportBaseline(fileContents: ""))
        XCTAssertNil(ModSettingsExportBaseline(fileContents: "  \n"))
    }

    func testFileContentsRoundTrip() {
        for original in [
            ModSettingsExportBaseline(hash: "abc123", path: movedPath),
            ModSettingsExportBaseline(hash: "abc123", path: nil),
        ] {
            XCTAssertEqual(ModSettingsExportBaseline(fileContents: original.fileContents), original)
        }
    }

    func testLegacyFileContentsAreHashOnly() {
        XCTAssertEqual(ModSettingsExportBaseline(hash: "abc123", path: nil).fileContents, "abc123")
    }

    // MARK: - Applicability

    func testBaselineAppliesToItsOwnPath() {
        let baseline = ModSettingsExportBaseline(hash: "abc123", path: movedPath)
        XCTAssertTrue(baseline.applies(to: movedPath, legacyPath: defaultPath))
    }

    func testBaselineDoesNotApplyToAnotherInstallation() {
        let baseline = ModSettingsExportBaseline(hash: "abc123", path: defaultPath)
        XCTAssertFalse(baseline.applies(to: movedPath, legacyPath: defaultPath))
    }

    func testLegacyBaselineAppliesOnlyToDefaultPath() {
        let baseline = ModSettingsExportBaseline(hash: "abc123", path: nil)
        XCTAssertTrue(baseline.applies(to: defaultPath, legacyPath: defaultPath))
        XCTAssertFalse(baseline.applies(to: movedPath, legacyPath: defaultPath))
    }
}
