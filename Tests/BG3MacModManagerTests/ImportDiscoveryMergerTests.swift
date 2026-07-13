// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class ImportDiscoveryMergerTests: XCTestCase {
    func testMergePreservesActiveOrderAndAddsNewModsAsInactive() {
        let activeA = makeModInfo(uuid: "active-a", name: "Old Active A")
        let activeB = makeModInfo(uuid: "active-b", name: "Old Active B")
        let inactive = makeModInfo(uuid: "inactive", name: "Old Inactive")
        let refreshedA = makeModInfo(uuid: "active-a", name: "Refreshed Active A")
        let refreshedB = makeModInfo(uuid: "active-b", name: "Refreshed Active B")
        let refreshedInactive = makeModInfo(uuid: "inactive", name: "Refreshed Inactive")
        let newMod = makeModInfo(uuid: "new", name: "New Mod")

        let result = ImportDiscoveryMerger.merge(
            previousActive: [activeB, activeA],
            previousInactive: [inactive],
            hadUnsavedChanges: false,
            discovered: [newMod, refreshedA, refreshedInactive, refreshedB]
        )

        XCTAssertEqual(result.active.map(\.uuid), ["active-b", "active-a"])
        XCTAssertEqual(result.active.map(\.name), ["Refreshed Active B", "Refreshed Active A"])
        XCTAssertEqual(result.inactive.map(\.uuid), ["inactive", "new"])
        XCTAssertEqual(result.inactive.first?.name, "Refreshed Inactive")
        XCTAssertEqual(result.newMods.map(\.uuid), ["new"])
        XCTAssertFalse(result.hasUnsavedChanges)
    }

    func testMergePreservesDirtyState() {
        let active = makeModInfo(uuid: "active")
        let newMod = makeModInfo(uuid: "new")

        let result = ImportDiscoveryMerger.merge(
            previousActive: [active],
            previousInactive: [],
            hadUnsavedChanges: true,
            discovered: [active, newMod]
        )

        XCTAssertEqual(result.active.map(\.uuid), ["active"])
        XCTAssertEqual(result.inactive.map(\.uuid), ["new"])
        XCTAssertTrue(result.hasUnsavedChanges)
    }

    func testMergeRetainsMissingActiveEntriesButDropsMissingInactiveEntries() {
        let missingActive = makeModInfo(uuid: "missing-active", name: "Missing Active")
        let missingInactive = makeModInfo(uuid: "missing-inactive", name: "Missing Inactive")
        let newMod = makeModInfo(uuid: "new", name: "New Mod")

        let result = ImportDiscoveryMerger.merge(
            previousActive: [missingActive],
            previousInactive: [missingInactive],
            hadUnsavedChanges: false,
            discovered: [newMod]
        )

        XCTAssertEqual(result.active, [missingActive])
        XCTAssertEqual(result.inactive, [newMod])
        XCTAssertEqual(result.newMods, [newMod])
    }

    func testMergeDoesNotTreatReplacementWithSameUUIDAsNew() {
        let previous = makeModInfo(uuid: "same-uuid", name: "Old Version", version64: 1)
        let replacement = makeModInfo(uuid: "same-uuid", name: "New Version", version64: 2)

        let result = ImportDiscoveryMerger.merge(
            previousActive: [],
            previousInactive: [previous],
            hadUnsavedChanges: false,
            discovered: [replacement]
        )

        XCTAssertEqual(result.inactive, [replacement])
        XCTAssertTrue(result.newMods.isEmpty)
    }
}
