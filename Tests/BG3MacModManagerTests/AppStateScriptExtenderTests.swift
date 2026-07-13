// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class AppStateScriptExtenderTests: XCTestCase {
    @MainActor
    func testApplyingDeployedStatusClearsStaleRequirementWarning() {
        let state = AppState()
        state.activeMods = [
            makeModInfo(
                uuid: "11111111-1111-1111-1111-111111111111",
                name: "Script Extender Mod",
                requiresScriptExtender: true
            ),
        ]

        state.runValidation()
        XCTAssertTrue(state.warnings.contains { $0.category == .seRequired })

        state.applySEStatus(makeSEStatus(isInstalled: true, isDeployed: true))

        XCTAssertFalse(state.warnings.contains { $0.category == .seRequired })
    }
}
