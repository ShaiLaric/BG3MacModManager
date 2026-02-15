// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class ModCategoryTests: XCTestCase {

    func testRawValues() {
        XCTAssertEqual(ModCategory.framework.rawValue, 1)
        XCTAssertEqual(ModCategory.gameplay.rawValue, 2)
        XCTAssertEqual(ModCategory.contentExtension.rawValue, 3)
        XCTAssertEqual(ModCategory.visual.rawValue, 4)
        XCTAssertEqual(ModCategory.lateLoader.rawValue, 5)
    }

    func testComparable() {
        XCTAssertTrue(ModCategory.framework < .gameplay)
        XCTAssertTrue(ModCategory.gameplay < .contentExtension)
        XCTAssertTrue(ModCategory.contentExtension < .visual)
        XCTAssertTrue(ModCategory.visual < .lateLoader)
    }

    func testCaseIterableCount() {
        XCTAssertEqual(ModCategory.allCases.count, 5)
    }

    func testDisplayNames() {
        XCTAssertEqual(ModCategory.framework.displayName, "Framework")
        XCTAssertEqual(ModCategory.gameplay.displayName, "Gameplay")
        XCTAssertEqual(ModCategory.contentExtension.displayName, "Content")
        XCTAssertEqual(ModCategory.visual.displayName, "Visual")
        XCTAssertEqual(ModCategory.lateLoader.displayName, "Late Loader")
    }

    func testCodableRoundTrip() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for category in ModCategory.allCases {
            let data = try encoder.encode(category)
            let decoded = try decoder.decode(ModCategory.self, from: data)
            XCTAssertEqual(decoded, category, "Round-trip failed for \(category)")
        }
    }

    func testSortOrder() {
        let unsorted: [ModCategory] = [.lateLoader, .framework, .visual, .gameplay, .contentExtension]
        let sorted = unsorted.sorted()
        XCTAssertEqual(sorted, [.framework, .gameplay, .contentExtension, .visual, .lateLoader])
    }
}
