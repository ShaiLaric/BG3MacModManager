// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class ActivationPositionTests: XCTestCase {

    func testActivationWithoutPositionAppends() async {
        await MainActor.run {
            let state = makeState()
            let pending = state.inactiveMods[0]

            state.activateMod(pending)

            XCTAssertEqual(state.activeMods.map(\.name), ["First", "Second", "Pending"])
            XCTAssertTrue(state.inactiveMods.isEmpty)
        }
    }

    func testActivationUsesOneBasedLoadOrderPosition() async {
        await MainActor.run {
            let state = makeState()
            let pending = state.inactiveMods[0]

            state.activateMod(pending, atLoadOrderPosition: 2)

            XCTAssertEqual(state.activeMods.map(\.name), ["First", "Pending", "Second"])
            XCTAssertEqual(state.statusMessage, "Activated Pending at load order position 2")
        }
    }

    func testActivationClampsOutOfRangePositionsSafely() async {
        await MainActor.run {
            let firstState = makeState()
            firstState.activateMod(firstState.inactiveMods[0], atLoadOrderPosition: 0)
            XCTAssertEqual(firstState.activeMods.map(\.name), ["Pending", "First", "Second"])

            let lastState = makeState()
            lastState.activateMod(lastState.inactiveMods[0], atLoadOrderPosition: 99)
            XCTAssertEqual(lastState.activeMods.map(\.name), ["First", "Second", "Pending"])
            XCTAssertEqual(lastState.statusMessage, "Activated Pending at load order position 3")
        }
    }

    func testDragInsertionRemainsZeroBased() async {
        await MainActor.run {
            let state = makeState()
            state.activateModAtPosition(state.inactiveMods[0], at: 1)
            XCTAssertEqual(state.activeMods.map(\.name), ["First", "Pending", "Second"])
        }
    }

    @MainActor
    private func makeState() -> AppState {
        let state = AppState()
        state.activeMods = [
            makeModInfo(uuid: "11111111-1111-1111-1111-111111111111", name: "First"),
            makeModInfo(uuid: "22222222-2222-2222-2222-222222222222", name: "Second"),
        ]
        state.inactiveMods = [
            makeModInfo(uuid: "33333333-3333-3333-3333-333333333333", name: "Pending"),
        ]
        return state
    }
}
