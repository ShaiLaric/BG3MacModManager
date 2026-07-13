// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class ModDiscoveryServiceTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var modsDirectory: URL!
    private var settingsURL: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModDiscoveryServiceTests-\(UUID().uuidString)")
        modsDirectory = temporaryDirectory.appendingPathComponent("Mods")
        settingsURL = temporaryDirectory.appendingPathComponent("modsettings.lsx")
        try FileManager.default.createDirectory(at: modsDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testDiscoveryPreservesPhysicalDuplicatesButCanonicalStateUsesOne() throws {
        let uuid = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        try writeMod(named: "First", uuid: uuid.uppercased())
        try writeMod(named: "Second", uuid: uuid)
        let service = ModDiscoveryService(
            modsFolder: modsDirectory,
            modSettingsURL: settingsURL
        )

        let physical = try service.discoverMods()
        let state = try service.discoverModsWithState()

        XCTAssertEqual(physical.count, 2)
        XCTAssertEqual(Set(physical.map(\.uuid)), [uuid])
        XCTAssertEqual(state.inactive.count, 1)
        XCTAssertEqual(state.duplicateGroups.count, 1)
        XCTAssertEqual(state.duplicateGroups.first?.count, 2)
    }

    func testActiveMatchingIsCaseInsensitiveAndPhantomUsesFolderMetadata() throws {
        let physicalUUID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
        let phantomUUID = "11111111-2222-3333-4444-555555555555"
        try writeMod(named: "Physical", uuid: physicalUUID)

        let settings = ModSettingsService.ModSettings(
            modOrder: [physicalUUID.uppercased(), phantomUUID.uppercased()],
            mods: [
                physicalUUID.uppercased(): .init(
                    folder: "PhysicalFolder",
                    md5: "",
                    name: "Physical",
                    uuid: physicalUUID.uppercased(),
                    version64: "36028797018963968"
                ),
                phantomUUID.uppercased(): .init(
                    folder: "ActualPhantomFolder",
                    md5: "",
                    name: "Phantom Display Name",
                    uuid: phantomUUID.uppercased(),
                    version64: "36028797018963968"
                ),
            ]
        )
        try ModSettingsService().write(settings, to: settingsURL)

        let state = try ModDiscoveryService(
            modsFolder: modsDirectory,
            modSettingsURL: settingsURL
        ).discoverModsWithState()

        XCTAssertEqual(state.active.map(\.uuid), [physicalUUID, phantomUUID])
        XCTAssertEqual(state.active.last?.folder, "ActualPhantomFolder")
        XCTAssertTrue(state.inactive.isEmpty)
    }

    func testInvalidMetadataUUIDGetsStableFilenameIdentity() throws {
        try writeMod(named: "BrokenUUID", uuid: "not-a-uuid")
        let service = ModDiscoveryService(
            modsFolder: modsDirectory,
            modSettingsURL: settingsURL
        )

        let first = try service.discoverMods()
        let second = try service.discoverMods()

        XCTAssertEqual(first.first?.uuid, second.first?.uuid)
        XCTAssertEqual(
            first.first?.uuid,
            ModInfo.deterministicUUID(from: "BrokenUUID.pak")
        )
    }

    func testRequiredGameComponentIsAlwaysActiveWithoutModSettings() throws {
        try writeMod(named: "Gustav", uuid: Constants.gustavUUID)
        try writeMod(named: "UserMod", uuid: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")

        let state = try ModDiscoveryService(
            modsFolder: modsDirectory,
            modSettingsURL: settingsURL
        ).discoverModsWithState()

        XCTAssertEqual(state.active.map(\.uuid), [Constants.gustavUUID])
        XCTAssertEqual(state.inactive.map(\.name), ["UserMod"])
    }

    func testPackagedBuiltInMetadataDoesNotHideTheActualMod() throws {
        let partyUUID = "08c0c2c1-d19f-1939-7af7-a1231317a6b0"
        let gustavMetadata = metadataXML(
            folder: "Gustav",
            name: "Gustav",
            uuid: Constants.gustavUUID
        )
        let partyMetadata = metadataXML(
            folder: "PartyLimitBegone",
            name: "Party Limit Begone",
            uuid: partyUUID
        )
        try makeUncompressedTestPak(entries: [
            ("Mods/Gustav/meta.lsx", gustavMetadata),
            ("Mods/PartyLimitBegone/meta.lsx", partyMetadata),
        ]).write(to: modsDirectory.appendingPathComponent("PartyLimitBegone.pak"))

        let settings = ModSettingsService.ModSettings(
            modOrder: [Constants.baseModuleUUID, partyUUID, Constants.gustavUUID],
            mods: [
                partyUUID: .init(
                    folder: "PartyLimitBegone",
                    md5: "",
                    name: "Party Limit Begone",
                    uuid: partyUUID,
                    version64: "36028797018963968"
                )
            ]
        )
        try ModSettingsService().write(settings, to: settingsURL)

        let state = try ModDiscoveryService(
            modsFolder: modsDirectory,
            modSettingsURL: settingsURL
        ).discoverModsWithState()

        XCTAssertEqual(state.active.map(\.uuid), [partyUUID])
        XCTAssertEqual(state.active.first?.name, "Party Limit Begone")
        XCTAssertTrue(state.inactive.isEmpty)
    }

    private func writeMod(named name: String, uuid: String) throws {
        try Data().write(to: modsDirectory.appendingPathComponent("\(name).pak"))
        let json = """
        {
          "mods": [{
            "modName": "\(name)",
            "folderName": "\(name)",
            "UUID": "\(uuid)",
            "version": "1.0.0.0"
          }]
        }
        """
        try Data(json.utf8).write(
            to: modsDirectory.appendingPathComponent("\(name).json")
        )
    }

    private func metadataXML(folder: String, name: String, uuid: String) -> Data {
        Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <save><node id="ModuleInfo">
          <attribute id="Folder" type="LSString" value="\(folder)"/>
          <attribute id="Name" type="LSString" value="\(name)"/>
          <attribute id="UUID" type="guid" value="\(uuid)"/>
          <attribute id="Version64" type="int64" value="36028797018963968"/>
        </node></save>
        """.utf8)
    }
}
