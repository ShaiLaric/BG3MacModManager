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

    func testPositionedActivationThatViolatesPersistentRuleIsRejected() async {
        await MainActor.run {
            let state = makeState()
            let pending = state.inactiveMods[0]
            state.loadOrderRules = [
                LoadOrderRule(kind: .pinFirst, sourceUUID: pending.uuid),
            ]

            state.activateMod(pending, atLoadOrderPosition: 3)

            XCTAssertEqual(state.activeMods.map(\.name), ["First", "Second"])
            XCTAssertEqual(state.inactiveMods.map(\.name), ["Pending"])
            XCTAssertTrue(state.showError)
            XCTAssertTrue(state.errorMessage?.contains("violates a load-order rule") == true)
        }
    }

    func testProfileLoadKeepsRequiredGameComponentActive() async {
        let defaults = UserDefaults.standard
        let key = AppPreferenceKey.autoSaveOnProfileLoad
        let priorValue = defaults.object(forKey: key)
        defaults.set(false, forKey: key)
        defer {
            if let priorValue {
                defaults.set(priorValue, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        let state = await MainActor.run { () -> AppState in
            let state = AppState()
            state.activeMods = [
                makeModInfo(
                    uuid: Constants.gustavUUID,
                    folder: "Gustav",
                    name: "Gustav"
                ),
                makeModInfo(uuid: "11111111-1111-1111-1111-111111111111", name: "Old"),
            ]
            state.inactiveMods = [
                makeModInfo(uuid: "22222222-2222-2222-2222-222222222222", name: "Profile Mod"),
            ]
            return state
        }
        let profileMod = await MainActor.run { state.inactiveMods[0] }
        let profile = ModProfile(
            name: "Test",
            activeModUUIDs: [profileMod.uuid],
            mods: [ModProfileEntry(from: profileMod)]
        )

        await state.loadProfile(profile)

        await MainActor.run {
            XCTAssertEqual(state.activeMods.map(\.uuid), [Constants.gustavUUID, profileMod.uuid])
            XCTAssertFalse(state.inactiveMods.contains(where: \.isBasicGameModule))
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
