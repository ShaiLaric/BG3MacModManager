// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class CategoryInferenceServiceTests: XCTestCase {

    var service: CategoryInferenceService!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategoryInferenceTests-\(UUID().uuidString).json")
        service = CategoryInferenceService(overridesURL: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    // MARK: - Tag Heuristics: Late Loader

    func testTagCompatibilityInfersLateLoader() {
        let mod = makeModInfo(tags: ["compatibility"])
        XCTAssertEqual(service.inferCategory(for: mod), .lateLoader)
    }

    func testTagPatchInfersLateLoader() {
        let mod = makeModInfo(tags: ["patch"])
        XCTAssertEqual(service.inferCategory(for: mod), .lateLoader)
    }

    func testTagCombinerInfersLateLoader() {
        let mod = makeModInfo(tags: ["combiner"])
        XCTAssertEqual(service.inferCategory(for: mod), .lateLoader)
    }

    // MARK: - Tag Heuristics: Framework

    func testTagFrameworkInfersFramework() {
        let mod = makeModInfo(tags: ["framework"])
        XCTAssertEqual(service.inferCategory(for: mod), .framework)
    }

    func testTagLibraryInfersFramework() {
        let mod = makeModInfo(tags: ["library"])
        XCTAssertEqual(service.inferCategory(for: mod), .framework)
    }

    func testTagAPIInfersFramework() {
        let mod = makeModInfo(tags: ["api"])
        XCTAssertEqual(service.inferCategory(for: mod), .framework)
    }

    func testTagMCMInfersFramework() {
        let mod = makeModInfo(tags: ["mcm"])
        XCTAssertEqual(service.inferCategory(for: mod), .framework)
    }

    // MARK: - Tag Heuristics: Visual

    func testTagCosmeticInfersVisual() {
        let mod = makeModInfo(tags: ["cosmetic"])
        XCTAssertEqual(service.inferCategory(for: mod), .visual)
    }

    func testTagHairInfersVisual() {
        let mod = makeModInfo(tags: ["hair"])
        XCTAssertEqual(service.inferCategory(for: mod), .visual)
    }

    func testTagTextureInfersVisual() {
        let mod = makeModInfo(tags: ["texture"])
        XCTAssertEqual(service.inferCategory(for: mod), .visual)
    }

    // MARK: - Tag Heuristics: Content Extension

    func testTagClassInfersContentExtension() {
        let mod = makeModInfo(tags: ["class"])
        XCTAssertEqual(service.inferCategory(for: mod), .contentExtension)
    }

    func testTagSpellInfersContentExtension() {
        let mod = makeModInfo(tags: ["spell"])
        XCTAssertEqual(service.inferCategory(for: mod), .contentExtension)
    }

    func testTagFeatInfersContentExtension() {
        let mod = makeModInfo(tags: ["feat"])
        XCTAssertEqual(service.inferCategory(for: mod), .contentExtension)
    }

    // MARK: - Tag Heuristics: Gameplay

    func testTagGameplayInfersGameplay() {
        let mod = makeModInfo(tags: ["gameplay"])
        XCTAssertEqual(service.inferCategory(for: mod), .gameplay)
    }

    func testTagFixInfersGameplay() {
        let mod = makeModInfo(tags: ["fix"])
        XCTAssertEqual(service.inferCategory(for: mod), .gameplay)
    }

    func testTagQoLInfersGameplay() {
        let mod = makeModInfo(tags: ["qol"])
        XCTAssertEqual(service.inferCategory(for: mod), .gameplay)
    }

    // MARK: - Tag Heuristics: No Match

    func testUnrelatedTagReturnsNil() {
        let mod = makeModInfo(tags: ["random_tag"])
        XCTAssertNil(service.inferCategory(for: mod))
    }

    func testEmptyTagsReturnsNil() {
        let mod = makeModInfo(name: "UnknownMod", tags: [])
        XCTAssertNil(service.inferCategory(for: mod))
    }

    // MARK: - Tag Priority: Late Loader Checked First

    func testLateLoaderTagTakesPriorityOverFramework() {
        // "compatibility" is a late loader signal, even alongside "framework"
        let mod = makeModInfo(tags: ["compatibility", "framework"])
        XCTAssertEqual(service.inferCategory(for: mod), .lateLoader)
    }

    // MARK: - Name Heuristics

    func testNameCommunityLibraryInfersFramework() {
        let mod = makeModInfo(name: "Community Library", tags: [])
        XCTAssertEqual(service.inferCategory(for: mod), .framework)
    }

    func testNameSpellListCombinerInfersLateLoader() {
        let mod = makeModInfo(name: "Spell List Combiner", tags: [])
        XCTAssertEqual(service.inferCategory(for: mod), .lateLoader)
    }

    func testNameCustomHairPackInfersVisual() {
        let mod = makeModInfo(name: "Custom Hair Pack", tags: [])
        XCTAssertEqual(service.inferCategory(for: mod), .visual)
    }

    func testNameNewSubclassInfersContentExtension() {
        let mod = makeModInfo(name: "Paladin Oath Subclass", tags: [])
        XCTAssertEqual(service.inferCategory(for: mod), .contentExtension)
    }

    func testNameAutoLootInfersGameplay() {
        let mod = makeModInfo(name: "Auto Loot Everything", tags: [])
        XCTAssertEqual(service.inferCategory(for: mod), .gameplay)
    }

    func testNamePatchSuffixInfersLateLoader() {
        // Name ending in " patch" with length > 10
        let mod = makeModInfo(name: "Some Other Mod Patch", tags: [])
        XCTAssertEqual(service.inferCategory(for: mod), .lateLoader)
    }

    // MARK: - Tag Takes Priority Over Name

    func testTagTakesPriorityOverName() {
        // Name sounds visual, but tag says framework
        let mod = makeModInfo(name: "Custom Hair Framework Override", tags: ["framework"])
        XCTAssertEqual(service.inferCategory(for: mod), .framework)
    }

    // MARK: - Override Behavior

    func testOverrideTakesPriority() {
        let uuid = "override-test-uuid"
        let mod = makeModInfo(uuid: uuid, tags: ["framework"])

        // Without override, tag-based inference
        XCTAssertEqual(service.inferCategory(for: mod), .framework)

        // Set override
        service.setOverride(.lateLoader, for: uuid)
        XCTAssertEqual(service.inferCategory(for: mod), .lateLoader)
    }

    func testClearOverride() {
        let uuid = "clear-test-uuid"
        let mod = makeModInfo(uuid: uuid, tags: ["gameplay"])

        service.setOverride(.visual, for: uuid)
        XCTAssertEqual(service.inferCategory(for: mod), .visual)

        // Clear override - should fall back to tag inference
        service.setOverride(nil, for: uuid)
        XCTAssertEqual(service.inferCategory(for: mod), .gameplay)
    }

    func testOverrideReturnsCorrectValue() {
        let uuid = "query-test-uuid"
        XCTAssertNil(service.override(for: uuid))

        service.setOverride(.contentExtension, for: uuid)
        XCTAssertEqual(service.override(for: uuid), .contentExtension)
    }

    // MARK: - Persistence Round-Trip

    func testOverridePersistsAcrossInstances() {
        let uuid = "persist-test-uuid"
        service.setOverride(.visual, for: uuid)

        // Create a second instance reading from the same file
        let service2 = CategoryInferenceService(overridesURL: tempURL)
        XCTAssertEqual(service2.override(for: uuid), .visual)
    }
}
