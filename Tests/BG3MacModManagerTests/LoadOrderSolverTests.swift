// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class LoadOrderSolverTests: XCTestCase {
    private let solver = LoadOrderSolver()

    func testRelativeRulesAreAppliedDeterministically() {
        let a = makeModInfo(uuid: "a", name: "A")
        let b = makeModInfo(uuid: "b", name: "B")
        let c = makeModInfo(uuid: "c", name: "C")
        let rules = [
            LoadOrderRule(kind: .before, sourceUUID: "c", targetUUID: "a"),
            LoadOrderRule(kind: .after, sourceUUID: "b", targetUUID: "a"),
        ]

        let result = solver.solve(mods: [a, b, c], rules: rules, mode: .dependenciesOnly)

        XCTAssertEqual(orderedUUIDs(result), ["c", "a", "b"])
    }

    func testDormantRuleDoesNotPreventSorting() {
        let a = makeModInfo(uuid: "a", name: "A")
        let rule = LoadOrderRule(kind: .before, sourceUUID: "missing", targetUUID: "a")

        XCTAssertEqual(
            orderedUUIDs(solver.solve(mods: [a], rules: [rule], mode: .smart)),
            ["a"]
        )
    }

    func testHardDependencyOverridesSmartCategoryPreferenceAcrossTiers() {
        let visualDependency = makeModInfo(uuid: "visual", name: "Visual", category: .visual)
        let frameworkDependent = makeModInfo(
            uuid: "framework",
            name: "Framework",
            dependencies: [makeDependency(uuid: "visual")],
            category: .framework
        )

        let result = solver.solve(
            mods: [frameworkDependent, visualDependency],
            mode: .smart
        )

        XCTAssertEqual(orderedUUIDs(result), ["visual", "framework"])
    }

    func testExistingOrderIsStableTieBreaker() {
        let mods = [
            makeModInfo(uuid: "c", name: "C"),
            makeModInfo(uuid: "a", name: "A"),
            makeModInfo(uuid: "b", name: "B"),
        ]

        XCTAssertEqual(
            orderedUUIDs(solver.solve(mods: mods, mode: .dependenciesOnly)),
            ["c", "a", "b"]
        )
    }

    func testRuleCycleReportsContributingRuleIDs() throws {
        let a = makeModInfo(uuid: "a", name: "A")
        let b = makeModInfo(uuid: "b", name: "B")
        let first = LoadOrderRule(kind: .before, sourceUUID: "a", targetUUID: "b")
        let second = LoadOrderRule(kind: .before, sourceUUID: "b", targetUUID: "a")

        let conflict = try XCTUnwrap(conflict(
            solver.solve(mods: [a, b], rules: [first, second], mode: .smart)
        ))

        XCTAssertEqual(conflict.kind, .cycle)
        XCTAssertEqual(Set(conflict.affectedModUUIDs), ["a", "b"])
        XCTAssertEqual(Set(conflict.ruleIDs), [first.id, second.id])
    }

    func testExactPinOccupiesRequestedPosition() {
        let mods = ["a", "b", "c", "d"].map { makeModInfo(uuid: $0, name: $0) }
        let rule = LoadOrderRule(kind: .pinPosition, sourceUUID: "d", position: 2)

        XCTAssertEqual(
            orderedUUIDs(solver.solve(mods: mods, rules: [rule], mode: .dependenciesOnly)),
            ["a", "d", "b", "c"]
        )
    }

    func testPinFirstAndPinLast() {
        let mods = ["a", "b", "c"].map { makeModInfo(uuid: $0, name: $0) }
        let rules = [
            LoadOrderRule(kind: .pinFirst, sourceUUID: "c"),
            LoadOrderRule(kind: .pinLast, sourceUUID: "a"),
        ]

        XCTAssertEqual(
            orderedUUIDs(solver.solve(mods: mods, rules: rules, mode: .dependenciesOnly)),
            ["c", "b", "a"]
        )
    }

    func testTwoModsCannotOccupyOnePinnedPosition() throws {
        let mods = ["a", "b"].map { makeModInfo(uuid: $0, name: $0) }
        let first = LoadOrderRule(kind: .pinPosition, sourceUUID: "a", position: 1)
        let second = LoadOrderRule(kind: .pinFirst, sourceUUID: "b")

        let conflict = try XCTUnwrap(conflict(
            solver.solve(mods: mods, rules: [first, second], mode: .smart)
        ))

        XCTAssertEqual(conflict.kind, .pinCollision)
        XCTAssertEqual(Set(conflict.ruleIDs), [first.id, second.id])
    }

    func testDependencyThatBlocksPinReturnsConflictWithoutPartialOrder() throws {
        let dependency = makeModInfo(uuid: "dependency", name: "Dependency")
        let dependent = makeModInfo(
            uuid: "dependent",
            name: "Dependent",
            dependencies: [makeDependency(uuid: dependency.uuid)]
        )
        let pin = LoadOrderRule(kind: .pinFirst, sourceUUID: dependent.uuid)

        let conflict = try XCTUnwrap(conflict(
            solver.solve(mods: [dependent, dependency], rules: [pin], mode: .smart)
        ))

        XCTAssertEqual(conflict.kind, .pinBlocked)
        XCTAssertEqual(Set(conflict.affectedModUUIDs), ["dependency", "dependent"])
    }

    func testViolationsUseUserModPositionsAndIgnoreBuiltIns() {
        let builtIn = ModInfo.baseGameModule
        let a = makeModInfo(uuid: "a", name: "A")
        let b = makeModInfo(uuid: "b", name: "B")
        let rule = LoadOrderRule(kind: .before, sourceUUID: "b", targetUUID: "a")

        let violations = LoadOrderSolver.violations(mods: [builtIn, a, b], rules: [rule])

        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(Set(violations[0].affectedModUUIDs), ["a", "b"])
        XCTAssertTrue(violations[0].message.contains("position 2"))
    }

    func testThousandModGraphCompletesQuickly() {
        let mods = (0..<1_000).map { index in
            let uuid = String(format: "mod-%04d", index)
            let dependencies = index == 0
                ? []
                : [makeDependency(uuid: String(format: "mod-%04d", index - 1))]
            return makeModInfo(uuid: uuid, name: uuid, dependencies: dependencies)
        }.reversed()
        let start = Date()

        let result = solver.solve(
            mods: Array(mods),
            mode: .smart
        )

        XCTAssertEqual(orderedUUIDs(result).count, 1_000)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0)
    }

    // MARK: - Uncategorized mods follow their neighbor

    func testUncategorizedModStaysAfterPrecedingNeighbor() {
        let mods = [
            makeModInfo(uuid: "visual", name: "Visual", category: .visual),
            makeModInfo(uuid: "unknown", name: "Unknown"),
            makeModInfo(uuid: "framework", name: "Framework", category: .framework),
        ]

        XCTAssertEqual(
            orderedUUIDs(solver.solve(mods: mods, mode: .smart)),
            ["framework", "visual", "unknown"]
        )
    }

    func testLeadingUncategorizedModFollowsNextCategorizedNeighbor() {
        let mods = [
            makeModInfo(uuid: "unknown", name: "Unknown"),
            makeModInfo(uuid: "late", name: "Late", category: .lateLoader),
            makeModInfo(uuid: "content", name: "Content", category: .contentExtension),
        ]

        XCTAssertEqual(
            orderedUUIDs(solver.solve(mods: mods, mode: .smart)),
            ["content", "unknown", "late"]
        )
    }

    func testAllUncategorizedModsKeepTheirOrder() {
        let mods = [
            makeModInfo(uuid: "c", name: "C"),
            makeModInfo(uuid: "a", name: "A"),
            makeModInfo(uuid: "b", name: "B"),
        ]

        XCTAssertEqual(orderedUUIDs(solver.solve(mods: mods, mode: .smart)), ["c", "a", "b"])
    }

    func testDependencyOverridesInheritedTier() {
        let mods = [
            makeModInfo(uuid: "framework", name: "Framework", category: .framework),
            makeModInfo(uuid: "unknown", name: "Unknown", dependencies: [makeDependency(uuid: "visual")]),
            makeModInfo(uuid: "visual", name: "Visual", category: .visual),
        ]

        XCTAssertEqual(
            orderedUUIDs(solver.solve(mods: mods, mode: .smart)),
            ["framework", "visual", "unknown"]
        )
    }

    func testEffectiveTiersCarryForwardThroughRunsOfUncategorizedMods() {
        let tiers = LoadOrderSolver.effectiveTiers(for: [
            makeModInfo(uuid: "lead", name: "Lead"),
            makeModInfo(uuid: "gameplay", name: "Gameplay", category: .gameplay),
            makeModInfo(uuid: "u1", name: "U1"),
            makeModInfo(uuid: "u2", name: "U2"),
            makeModInfo(uuid: "visual", name: "Visual", category: .visual),
            makeModInfo(uuid: "u3", name: "U3"),
        ])

        XCTAssertEqual(tiers["lead"], ModCategory.gameplay.rawValue)
        XCTAssertEqual(tiers["u1"], ModCategory.gameplay.rawValue)
        XCTAssertEqual(tiers["u2"], ModCategory.gameplay.rawValue)
        XCTAssertEqual(tiers["u3"], ModCategory.visual.rawValue)
        XCTAssertEqual(tiers["visual"], ModCategory.visual.rawValue)
    }

    private func orderedUUIDs(_ result: LoadOrderSolver.Result) -> [String] {
        guard case .ordered(let mods) = result else { return [] }
        return mods.map(\.uuid)
    }

    private func conflict(_ result: LoadOrderSolver.Result) -> LoadOrderSolver.Conflict? {
        guard case .conflict(let conflict) = result else { return nil }
        return conflict
    }
}
