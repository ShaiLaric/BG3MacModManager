// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class LoadOrderRuleServiceTests: XCTestCase {
    private var directory: URL!
    private var url: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LoadOrderRuleServiceTests-\(UUID().uuidString)")
        url = directory.appendingPathComponent("rules.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testRulesPersistAcrossServiceInstancesIncludingDormantTargets() throws {
        let rule = LoadOrderRule(
            kind: .before,
            sourceUUID: "SOURCE",
            targetUUID: "NOT-INSTALLED"
        )
        try LoadOrderRuleService(url: url).saveRules([rule])

        let loaded = try LoadOrderRuleService(url: url).loadRules()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, rule.id)
        XCTAssertEqual(loaded[0].kind, rule.kind)
        XCTAssertEqual(loaded[0].sourceUUID, "source")
        XCTAssertEqual(loaded[0].targetUUID, "not-installed")
    }

    func testRuleValidationRejectsSelfReferenceAndInvalidPosition() {
        let service = LoadOrderRuleService(url: url)

        XCTAssertThrowsError(try service.validate(
            LoadOrderRule(kind: .before, sourceUUID: "same", targetUUID: "same")
        ))
        XCTAssertThrowsError(try service.validate(
            LoadOrderRule(kind: .pinPosition, sourceUUID: "mod", position: 0)
        ))
    }

    func testBuiltInModulesCannotBeRuleTargets() {
        let service = LoadOrderRuleService(url: url)
        let rule = LoadOrderRule(
            kind: .after,
            sourceUUID: "mod",
            targetUUID: Constants.baseModuleUUID
        )

        XCTAssertThrowsError(try service.validate(rule))
    }
}
