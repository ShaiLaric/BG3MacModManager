// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class ModInfoTests: XCTestCase {

    // MARK: - Base Game Module

    func testBaseGameModuleHasCorrectUUID() {
        let base = ModInfo.baseGameModule
        XCTAssertEqual(base.uuid, Constants.baseModuleUUID)
    }

    func testBaseGameModuleHasCorrectProperties() {
        let base = ModInfo.baseGameModule
        XCTAssertEqual(base.name, "GustavX")
        XCTAssertEqual(base.folder, "GustavX")
        XCTAssertEqual(base.author, "Larian Studios")
        XCTAssertEqual(base.metadataSource, .builtIn)
        XCTAssertEqual(base.version64, Constants.baseModuleVersion64)
    }

    func testBaseGameModuleIsBasicGameModule() {
        XCTAssertTrue(ModInfo.baseGameModule.isBasicGameModule)
    }

    func testGustavDevUUIDIsBasicGameModule() {
        let mod = makeModInfo(uuid: Constants.gustavDevUUID)
        XCTAssertTrue(mod.isBasicGameModule)
    }

    func testNonGameModuleIsNotBasicGameModule() {
        let mod = makeModInfo(uuid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        XCTAssertFalse(mod.isBasicGameModule)
    }

    // MARK: - fromPakFilename Factory

    func testFromPakFilenameProperties() {
        let url = URL(fileURLWithPath: "/tmp/CoolMod.pak")
        let mod = ModInfo.fromPakFilename("CoolMod.pak", at: url)

        XCTAssertEqual(mod.name, "CoolMod")
        XCTAssertEqual(mod.folder, "CoolMod")
        XCTAssertEqual(mod.author, "Unknown")
        XCTAssertEqual(mod.metadataSource, .filename)
        XCTAssertEqual(mod.pakFileName, "CoolMod.pak")
        XCTAssertEqual(mod.pakFilePath, url)
    }

    func testFromPakFilenameDeterministicUUID() {
        let url = URL(fileURLWithPath: "/tmp/CoolMod.pak")
        let mod1 = ModInfo.fromPakFilename("CoolMod.pak", at: url)
        let mod2 = ModInfo.fromPakFilename("CoolMod.pak", at: url)
        XCTAssertEqual(mod1.uuid, mod2.uuid)
    }

    func testFromPakFilenameDifferentFilesProduceDifferentUUIDs() {
        let url = URL(fileURLWithPath: "/tmp/")
        let mod1 = ModInfo.fromPakFilename("ModA.pak", at: url)
        let mod2 = ModInfo.fromPakFilename("ModB.pak", at: url)
        XCTAssertNotEqual(mod1.uuid, mod2.uuid)
    }

    func testFromPakFilenameCaseInsensitiveUUID() {
        let url = URL(fileURLWithPath: "/tmp/")
        let mod1 = ModInfo.fromPakFilename("CoolMod.pak", at: url)
        let mod2 = ModInfo.fromPakFilename("coolmod.pak", at: url)
        XCTAssertEqual(mod1.uuid, mod2.uuid)
    }

    // MARK: - Computed Properties

    func testVersionComputedProperty() {
        let mod = makeModInfo(version64: 36028797018963968)
        let expected = Version64(major: 1, minor: 0, revision: 0, build: 0)
        XCTAssertEqual(mod.version, expected)
    }

    // MARK: - MetadataSource Priority

    func testMetadataSourcePriorityOrder() {
        XCTAssertGreaterThan(MetadataSource.builtIn.priority, MetadataSource.metaLsx.priority)
        XCTAssertGreaterThan(MetadataSource.metaLsx.priority, MetadataSource.infoJson.priority)
        XCTAssertGreaterThan(MetadataSource.infoJson.priority, MetadataSource.modSettings.priority)
        XCTAssertGreaterThan(MetadataSource.modSettings.priority, MetadataSource.filename.priority)
    }

    func testMetadataSourceCodableRoundTrip() throws {
        let sources: [MetadataSource] = [.infoJson, .metaLsx, .filename, .builtIn, .modSettings]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for source in sources {
            let data = try encoder.encode(source)
            let decoded = try decoder.decode(MetadataSource.self, from: data)
            XCTAssertEqual(decoded, source, "Round-trip failed for \(source)")
        }
    }

    // MARK: - Constants

    func testBuiltInModuleUUIDsContainsKnownUUIDs() {
        XCTAssertTrue(Constants.builtInModuleUUIDs.contains(Constants.baseModuleUUID))
        XCTAssertTrue(Constants.builtInModuleUUIDs.contains(Constants.gustavDevUUID))
    }

    func testBuiltInModuleUUIDsCount() {
        XCTAssertEqual(Constants.builtInModuleUUIDs.count, 19)
    }
}
