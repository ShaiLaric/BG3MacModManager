// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class ModValidationServiceTests: XCTestCase {

    var service: ModValidationService!

    override func setUp() {
        super.setUp()
        service = ModValidationService()
    }

    /// Helper: filter warnings by category from a validate() result.
    private func warnings(
        _ category: ModWarning.Category,
        activeMods: [ModInfo] = [],
        inactiveMods: [ModInfo] = [],
        seStatus: ScriptExtenderService.SEStatus? = nil,
        seWasPreviouslyDeployed: Bool = false
    ) -> [ModWarning] {
        service.validate(
            activeMods: activeMods,
            inactiveMods: inactiveMods,
            seStatus: seStatus,
            seWasPreviouslyDeployed: seWasPreviouslyDeployed
        ).filter { $0.category == category }
    }

    // MARK: - Duplicate UUIDs

    func testNoDuplicatesNoWarning() {
        let modA = makeModInfo(uuid: "aaa", name: "Mod A")
        let modB = makeModInfo(uuid: "bbb", name: "Mod B")
        let result = warnings(.duplicateUUID, activeMods: [modA, modB])
        XCTAssertTrue(result.isEmpty)
    }

    func testDuplicateUUIDInActiveMods() {
        let modA = makeModInfo(uuid: "same-uuid", name: "Mod A", pakFileName: "A.pak")
        let modB = makeModInfo(uuid: "same-uuid", name: "Mod B", pakFileName: "B.pak")
        let result = warnings(.duplicateUUID, activeMods: [modA, modB])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.severity, .critical)
    }

    func testDuplicateUUIDCrossActiveInactive() {
        let active = makeModInfo(uuid: "same-uuid", name: "Active", pakFileName: "A.pak")
        let inactive = makeModInfo(uuid: "same-uuid", name: "Inactive", pakFileName: "B.pak")
        let result = warnings(.duplicateUUID, activeMods: [active], inactiveMods: [inactive])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.severity, .critical)
    }

    // MARK: - Missing Dependencies

    func testNoDependenciesNoWarning() {
        let mod = makeModInfo(uuid: "aaa", name: "No Deps")
        let result = warnings(.missingDependency, activeMods: [mod])
        XCTAssertTrue(result.isEmpty)
    }

    func testMissingDependencyNotInstalled() {
        let depUUID = "dep-uuid-missing"
        let dep = makeDependency(uuid: depUUID, name: "Missing Dep")
        let mod = makeModInfo(uuid: "aaa", name: "Mod A", dependencies: [dep])
        let result = warnings(.missingDependency, activeMods: [mod])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.severity, .warning)
        XCTAssertTrue(result.first?.message.contains("Missing Dep") ?? false)
    }

    func testDependencyInInactiveListSuggestsActivation() {
        let depUUID = "dep-uuid-inactive"
        let dep = makeDependency(uuid: depUUID, name: "Inactive Dep")
        let mod = makeModInfo(uuid: "aaa", name: "Mod A", dependencies: [dep])
        let inactiveMod = makeModInfo(uuid: depUUID, name: "Inactive Dep")
        let result = warnings(.missingDependency, activeMods: [mod], inactiveMods: [inactiveMod])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.suggestedAction, .activateDependencies(modUUID: "aaa"))
    }

    func testDependencyInActiveListNoWarning() {
        let depUUID = "dep-uuid-active"
        let dep = makeDependency(uuid: depUUID, name: "Active Dep")
        let mod = makeModInfo(uuid: "aaa", name: "Mod A", dependencies: [dep])
        let depMod = makeModInfo(uuid: depUUID, name: "Active Dep")
        let result = warnings(.missingDependency, activeMods: [mod, depMod])
        XCTAssertTrue(result.isEmpty)
    }

    func testBuiltInDependencyIgnored() {
        let builtInUUID = Constants.builtInModuleUUIDs.first!
        let dep = makeDependency(uuid: builtInUUID, name: "Built-in")
        let mod = makeModInfo(uuid: "aaa", name: "Mod A", dependencies: [dep])
        let result = warnings(.missingDependency, activeMods: [mod])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Dependency Load Order

    func testCorrectDependencyOrderNoWarning() {
        let depUUID = "dep-uuid"
        let dep = makeDependency(uuid: depUUID, name: "Dep")
        let depMod = makeModInfo(uuid: depUUID, name: "Dep") // position 0
        let mod = makeModInfo(uuid: "aaa", name: "Mod A", dependencies: [dep]) // position 1
        let result = warnings(.wrongLoadOrder, activeMods: [depMod, mod])
        XCTAssertTrue(result.isEmpty)
    }

    func testWrongDependencyOrderWarning() {
        let depUUID = "dep-uuid"
        let dep = makeDependency(uuid: depUUID, name: "Dep")
        let mod = makeModInfo(uuid: "aaa", name: "Mod A", dependencies: [dep]) // position 0
        let depMod = makeModInfo(uuid: depUUID, name: "Dep") // position 1 (after dependent)
        let result = warnings(.wrongLoadOrder, activeMods: [mod, depMod])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.severity, .warning)
        XCTAssertEqual(result.first?.suggestedAction, .autoSort)
    }

    func testBuiltInDependencyOrderIgnored() {
        let builtInUUID = Constants.builtInModuleUUIDs.first!
        let dep = makeDependency(uuid: builtInUUID, name: "Built-in")
        let mod = makeModInfo(uuid: "aaa", name: "Mod A", dependencies: [dep])
        let result = warnings(.wrongLoadOrder, activeMods: [mod])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Circular Dependencies

    func testNoCycleNoWarning() {
        let depUUID = "dep-uuid"
        let dep = makeDependency(uuid: depUUID, name: "Dep")
        let modA = makeModInfo(uuid: "aaa", name: "Mod A", dependencies: [dep])
        let modB = makeModInfo(uuid: depUUID, name: "Dep")
        let result = warnings(.circularDependency, activeMods: [modA, modB])
        XCTAssertTrue(result.isEmpty)
    }

    func testDirectCycleWarning() {
        let depAB = makeDependency(uuid: "bbb", name: "Mod B")
        let depBA = makeDependency(uuid: "aaa", name: "Mod A")
        let modA = makeModInfo(uuid: "aaa", name: "Mod A", dependencies: [depAB])
        let modB = makeModInfo(uuid: "bbb", name: "Mod B", dependencies: [depBA])
        let result = warnings(.circularDependency, activeMods: [modA, modB])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.severity, .critical)
    }

    func testTransitiveCycleWarning() {
        let depAB = makeDependency(uuid: "bbb", name: "B")
        let depBC = makeDependency(uuid: "ccc", name: "C")
        let depCA = makeDependency(uuid: "aaa", name: "A")
        let modA = makeModInfo(uuid: "aaa", name: "A", dependencies: [depAB])
        let modB = makeModInfo(uuid: "bbb", name: "B", dependencies: [depBC])
        let modC = makeModInfo(uuid: "ccc", name: "C", dependencies: [depCA])
        let result = warnings(.circularDependency, activeMods: [modA, modB, modC])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.severity, .critical)
    }

    // MARK: - Conflicting Mods

    func testNoConflictsNoWarning() {
        let modA = makeModInfo(uuid: "aaa", name: "Mod A")
        let modB = makeModInfo(uuid: "bbb", name: "Mod B")
        let result = warnings(.conflictingMods, activeMods: [modA, modB])
        XCTAssertTrue(result.isEmpty)
    }

    func testConflictBothActiveWarning() {
        let conflictB = makeDependency(uuid: "bbb", name: "Mod B")
        let modA = makeModInfo(uuid: "aaa", name: "Mod A", conflicts: [conflictB])
        let modB = makeModInfo(uuid: "bbb", name: "Mod B")
        let result = warnings(.conflictingMods, activeMods: [modA, modB])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.severity, .warning)
    }

    func testConflictOneInactiveNoWarning() {
        let conflictB = makeDependency(uuid: "bbb", name: "Mod B")
        let modA = makeModInfo(uuid: "aaa", name: "Mod A", conflicts: [conflictB])
        let modB = makeModInfo(uuid: "bbb", name: "Mod B")
        let result = warnings(.conflictingMods, activeMods: [modA], inactiveMods: [modB])
        XCTAssertTrue(result.isEmpty)
    }

    func testMutualConflictOnlyOneWarning() {
        let conflictB = makeDependency(uuid: "bbb", name: "Mod B")
        let conflictA = makeDependency(uuid: "aaa", name: "Mod A")
        let modA = makeModInfo(uuid: "aaa", name: "Mod A", conflicts: [conflictB])
        let modB = makeModInfo(uuid: "bbb", name: "Mod B", conflicts: [conflictA])
        let result = warnings(.conflictingMods, activeMods: [modA, modB])
        XCTAssertEqual(result.count, 1) // Deduped via canonical pair
    }

    // MARK: - Phantom Mods

    func testPhantomModWarning() {
        let mod = makeModInfo(uuid: "aaa", name: "Phantom", metadataSource: .modSettings)
        let result = warnings(.phantomMod, activeMods: [mod])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.severity, .critical)
    }

    func testNonPhantomModNoWarning() {
        let mod = makeModInfo(uuid: "aaa", name: "Real Mod", metadataSource: .metaLsx)
        let result = warnings(.phantomMod, activeMods: [mod])
        XCTAssertTrue(result.isEmpty)
    }

    func testBaseGameModuleNotPhantom() {
        // Base game module with modSettings source should NOT be flagged
        let mod = makeModInfo(
            uuid: Constants.baseModuleUUID,
            name: "GustavX",
            metadataSource: .modSettings
        )
        let result = warnings(.phantomMod, activeMods: [mod])
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Script Extender Requirements

    func testSERequiredButNotDeployed() {
        let mod = makeModInfo(uuid: "aaa", name: "SE Mod", requiresScriptExtender: true)
        let status = makeSEStatus(isDeployed: false)
        let result = warnings(.seRequired, activeMods: [mod], seStatus: status)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.severity, .critical)
        XCTAssertEqual(result.first?.suggestedAction, .installScriptExtender)
    }

    func testSERequiredAndDeployed() {
        let mod = makeModInfo(uuid: "aaa", name: "SE Mod", requiresScriptExtender: true)
        let status = makeSEStatus(isDeployed: true)
        let result = warnings(.seRequired, activeMods: [mod], seStatus: status)
        XCTAssertTrue(result.isEmpty)
    }

    func testSERequiredNilStatus() {
        let mod = makeModInfo(uuid: "aaa", name: "SE Mod", requiresScriptExtender: true)
        let result = warnings(.seRequired, activeMods: [mod], seStatus: nil)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.severity, .critical)
    }

    func testNoSEModsNoWarning() {
        let mod = makeModInfo(uuid: "aaa", name: "Normal Mod", requiresScriptExtender: false)
        let result = warnings(.seRequired, activeMods: [mod], seStatus: nil)
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - No Metadata

    func testNoMetadataModWarning() {
        let mod = makeModInfo(uuid: "aaa", name: "No Meta", metadataSource: .filename)
        let result = warnings(.noMetadata, activeMods: [mod])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.severity, .info)
    }

    func testMetadataModNoWarning() {
        let mod = makeModInfo(uuid: "aaa", name: "Has Meta", metadataSource: .metaLsx)
        let result = warnings(.noMetadata, activeMods: [mod])
        XCTAssertTrue(result.isEmpty)
    }

    func testNoMetadataInInactiveMods() {
        let mod = makeModInfo(uuid: "aaa", name: "No Meta Inactive", metadataSource: .filename)
        let result = warnings(.noMetadata, inactiveMods: [mod])
        XCTAssertEqual(result.count, 1)
    }

    // MARK: - SE Disappeared

    func testSEDisappearedWarning() {
        let status = makeSEStatus(isDeployed: false)
        let result = warnings(
            .seDisappeared,
            seStatus: status,
            seWasPreviouslyDeployed: true
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.severity, .warning)
        XCTAssertEqual(result.first?.suggestedAction, .viewSEStatus)
    }

    func testSENotPreviouslyDeployedNoWarning() {
        let status = makeSEStatus(isDeployed: false)
        let result = warnings(
            .seDisappeared,
            seStatus: status,
            seWasPreviouslyDeployed: false
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testSEStillDeployedNoWarning() {
        let status = makeSEStatus(isDeployed: true)
        let result = warnings(
            .seDisappeared,
            seStatus: status,
            seWasPreviouslyDeployed: true
        )
        XCTAssertTrue(result.isEmpty)
    }

    // MARK: - Topological Sort

    func testTopologicalSortNoDependencies() {
        let modA = makeModInfo(uuid: "aaa", name: "A")
        let modB = makeModInfo(uuid: "bbb", name: "B")
        let sorted = service.topologicalSort(mods: [modA, modB])
        XCTAssertNotNil(sorted)
        XCTAssertEqual(sorted?.count, 2)
    }

    func testTopologicalSortSimpleChain() {
        let dep = makeDependency(uuid: "bbb", name: "B")
        let modA = makeModInfo(uuid: "aaa", name: "A", dependencies: [dep])
        let modB = makeModInfo(uuid: "bbb", name: "B")

        let sorted = service.topologicalSort(mods: [modA, modB])
        XCTAssertNotNil(sorted)
        // B should come before A since A depends on B
        let indexB = sorted!.firstIndex(where: { $0.uuid == "bbb" })!
        let indexA = sorted!.firstIndex(where: { $0.uuid == "aaa" })!
        XCTAssertTrue(indexB < indexA)
    }

    func testTopologicalSortCycleReturnsNil() {
        let depAB = makeDependency(uuid: "bbb", name: "B")
        let depBA = makeDependency(uuid: "aaa", name: "A")
        let modA = makeModInfo(uuid: "aaa", name: "A", dependencies: [depAB])
        let modB = makeModInfo(uuid: "bbb", name: "B", dependencies: [depBA])

        let sorted = service.topologicalSort(mods: [modA, modB])
        XCTAssertNil(sorted)
    }

    func testTopologicalSortIgnoresExternalDependencies() {
        // Dependency on a UUID not in the input array should be ignored
        let externalDep = makeDependency(uuid: "external-uuid", name: "External")
        let modA = makeModInfo(uuid: "aaa", name: "A", dependencies: [externalDep])

        let sorted = service.topologicalSort(mods: [modA])
        XCTAssertNotNil(sorted)
        XCTAssertEqual(sorted?.count, 1)
    }

    // MARK: - Aggregate / validateForSave

    func testValidateForSaveFiltersInfoSeverity() {
        // Create a mod that triggers .info (no metadata) and .warning (missing dep)
        let dep = makeDependency(uuid: "missing-dep", name: "Missing")
        let mod = makeModInfo(
            uuid: "aaa",
            name: "Test Mod",
            dependencies: [dep],
            metadataSource: .filename
        )

        let allWarnings = service.validate(
            activeMods: [mod],
            inactiveMods: [],
            seStatus: nil
        )
        let infoWarnings = allWarnings.filter { $0.severity == .info }
        XCTAssertFalse(infoWarnings.isEmpty, "Should have at least one info warning")

        let saveWarnings = service.validateForSave(
            activeMods: [mod],
            inactiveMods: [],
            seStatus: nil
        )
        let saveInfoWarnings = saveWarnings.filter { $0.severity == .info }
        XCTAssertTrue(saveInfoWarnings.isEmpty, "validateForSave should exclude info severity")
    }

    func testValidateReturnsSortedBySeverity() {
        // Create conditions that produce both critical and info warnings
        let phantomMod = makeModInfo(uuid: "phantom", name: "Phantom", metadataSource: .modSettings)
        let noMetaMod = makeModInfo(uuid: "nometa", name: "No Meta", metadataSource: .filename)

        let allWarnings = service.validate(
            activeMods: [phantomMod, noMetaMod],
            inactiveMods: [],
            seStatus: nil
        )

        // Verify sorted: critical first, then warning, then info
        var lastSeverity: ModWarning.Severity = .critical
        for warning in allWarnings {
            XCTAssertTrue(
                warning.severity <= lastSeverity,
                "Warnings should be sorted by severity descending"
            )
            lastSeverity = warning.severity
        }
    }
}
