// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import BG3MacModManager

final class AppStateScanTests: XCTestCase {
    @MainActor
    func testImportPreservesActivationMadeDuringDiscoveryAndBlocksOverlappingMutation() async {
        let a = makeModInfo(uuid: "a")
        let b = makeModInfo(uuid: "b")
        let started = expectation(description: "scan started")
        let gate = DispatchSemaphore(value: 0)
        let state = AppState(nexusCredentialStore: TestNexusCredentialStore())
        state.modImportService = SuccessfulTestImporter()
        state.discoveryService = GatedDiscovery(mods: [a, b], gate: gate, started: started)
        state.inactiveMods = [a]
        let task = Task { await state.importMods(from: []) }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertFalse(state.canChangeLocations)
        let saved = await state.performSave()
        XCTAssertFalse(saved)
        state.activateMod(a)
        gate.signal()
        await task.value
        XCTAssertEqual(state.activeMods.map(\.uuid), ["a"])
        XCTAssertEqual(state.inactiveMods.map(\.uuid), ["b"])
        XCTAssertTrue(state.hasUnsavedChanges)
        XCTAssertNotNil(state.importHealthReport)
        XCTAssertFalse(state.canChangeLocations)
        state.finishImportHealthReview(activate: false)
        XCTAssertTrue(state.canChangeLocations)
    }

    @MainActor
    func testOlderRefreshCannotOverwriteNewerScanResult() async {
        let a = makeModInfo(uuid: "a")
        let b = makeModInfo(uuid: "b")
        let started = expectation(description: "old scan started")
        let gate = DispatchSemaphore(value: 0)
        let state = AppState(nexusCredentialStore: TestNexusCredentialStore())
        state.discoveryService = GatedDiscovery(mods: [a], gate: gate, started: started)
        let old = Task { await state.refreshMods() }
        await fulfillment(of: [started], timeout: 2)
        state.discoveryService = GatedDiscovery(mods: [b])
        await state.refreshMods()
        gate.signal()
        await old.value
        XCTAssertEqual(state.inactiveMods.map(\.uuid), ["b"])
    }
}

private struct SuccessfulTestImporter: ModImporting {
    func importMods(from urls: [URL], to modsFolder: URL) -> ModImportService.Result {
        .init(importedCount: 1)
    }
}

private struct GatedDiscovery: ModDiscovering {
    let mods: [ModInfo]
    var gate: DispatchSemaphore? = nil
    var started: XCTestExpectation? = nil
    private func pause() {
        started?.fulfill()
        if let gate { _ = gate.wait(timeout: .now() + 5) }
    }
    func discoverMods() throws -> [ModInfo] { mods }
    func discoverCanonicalMods() throws -> [ModInfo] { pause(); return mods }
    func discoverModsWithState() throws -> ModDiscoveryService.DiscoveryState {
        pause()
        return .init(active: [], inactive: mods, duplicateGroups: [])
    }
}
