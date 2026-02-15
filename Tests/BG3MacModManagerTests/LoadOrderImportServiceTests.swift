// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class LoadOrderImportServiceTests: XCTestCase {

    var service: LoadOrderImportService!
    var tempFiles: [URL] = []

    override func setUp() {
        super.setUp()
        service = LoadOrderImportService()
    }

    override func tearDown() {
        for url in tempFiles {
            try? FileManager.default.removeItem(at: url)
        }
        tempFiles.removeAll()
        super.tearDown()
    }

    /// Write a temporary file and track it for cleanup.
    private func writeTempFile(name: String, content: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bg3test_\(UUID().uuidString)_\(name)")
        try! content.write(to: url, atomically: true, encoding: .utf8)
        tempFiles.append(url)
        return url
    }

    // MARK: - BG3MM JSON Parsing

    private let sampleJSON = """
    {
        "mods": [
            {
                "modName": "Test Mod",
                "UUID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                "folder": "TestMod",
                "version": "36028797018963968",
                "md5": "abc123"
            },
            {
                "modName": "Another Mod",
                "UUID": "11111111-2222-3333-4444-555555555555",
                "folder": "AnotherMod",
                "version": "36028797018963968",
                "md5": "def456"
            }
        ]
    }
    """

    func testParseBG3MMJSON() throws {
        let url = writeTempFile(name: "loadorder.json", content: sampleJSON)
        let result = try service.parseFile(at: url)

        XCTAssertEqual(result.format, .bg3mm)
        XCTAssertEqual(result.entries.count, 2)
        XCTAssertEqual(result.sourceName, "BG3 Mod Manager")
    }

    func testParseBG3MMJSONLowercasesUUIDs() throws {
        let url = writeTempFile(name: "loadorder.json", content: sampleJSON)
        let result = try service.parseFile(at: url)

        for entry in result.entries {
            XCTAssertEqual(entry.uuid, entry.uuid.lowercased(),
                           "UUID should be lowercased: \(entry.uuid)")
        }
    }

    func testParseBG3MMJSONFiltersBuiltInUUIDs() throws {
        let builtInUUID = Constants.baseModuleUUID
        let json = """
        {
            "mods": [
                {
                    "modName": "GustavX",
                    "UUID": "\(builtInUUID)",
                    "folder": "GustavX",
                    "version": "36028797018963968",
                    "md5": ""
                },
                {
                    "modName": "Real Mod",
                    "UUID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                    "folder": "RealMod",
                    "version": "36028797018963968",
                    "md5": "abc"
                }
            ]
        }
        """
        let url = writeTempFile(name: "loadorder.json", content: json)
        let result = try service.parseFile(at: url)

        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.name, "Real Mod")
    }

    func testParseEmptyModListThrows() {
        // All mods are built-in, so after filtering the list is empty
        let builtInUUID = Constants.baseModuleUUID
        let json = """
        {
            "mods": [
                {
                    "modName": "GustavX",
                    "UUID": "\(builtInUUID)",
                    "folder": "GustavX",
                    "version": "36028797018963968",
                    "md5": ""
                }
            ]
        }
        """
        let url = writeTempFile(name: "empty.json", content: json)

        XCTAssertThrowsError(try service.parseFile(at: url)) { error in
            XCTAssertTrue(error is LoadOrderImportService.ImportError)
        }
    }

    func testParseInvalidJSONThrows() {
        let url = writeTempFile(name: "bad.json", content: "{ not valid json }")

        XCTAssertThrowsError(try service.parseFile(at: url)) { error in
            XCTAssertTrue(error is LoadOrderImportService.ImportError)
        }
    }

    func testParseUnknownFormatThrows() {
        let url = writeTempFile(name: "loadorder.txt", content: "some text")

        XCTAssertThrowsError(try service.parseFile(at: url)) { error in
            XCTAssertTrue(error is LoadOrderImportService.ImportError)
        }
    }

    func testImportedModEntryFields() throws {
        let json = """
        {
            "mods": [
                {
                    "modName": "My Mod",
                    "UUID": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
                    "folder": "MyModFolder",
                    "version": "72057594037927936",
                    "md5": "hash123"
                }
            ]
        }
        """
        let url = writeTempFile(name: "fields.json", content: json)
        let result = try service.parseFile(at: url)

        let entry = result.entries.first!
        XCTAssertEqual(entry.uuid, "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        XCTAssertEqual(entry.name, "My Mod")
        XCTAssertEqual(entry.folder, "MyModFolder")
        XCTAssertEqual(entry.version64, 72057594037927936)
        XCTAssertEqual(entry.md5, "hash123")
    }

    func testVersionFallbackToDefault() throws {
        let json = """
        {
            "mods": [
                {
                    "modName": "Bad Version",
                    "UUID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
                    "folder": "BadVer",
                    "version": "not_a_number",
                    "md5": ""
                }
            ]
        }
        """
        let url = writeTempFile(name: "badversion.json", content: json)
        let result = try service.parseFile(at: url)

        XCTAssertEqual(result.entries.first?.version64, 36028797018963968)
    }

    // MARK: - LSX Parsing

    func testParseLSXFile() throws {
        let lsx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <save>
            <version major="4" minor="8" revision="0" build="500"/>
            <region id="ModuleSettings">
                <node id="root">
                    <children>
                        <node id="ModOrder">
                            <children>
                                <node id="Module">
                                    <attribute id="UUID" type="guid" value="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"/>
                                </node>
                            </children>
                        </node>
                        <node id="Mods">
                            <children>
                                <node id="ModuleShortDesc">
                                    <attribute id="Folder" type="LSString" value="TestMod"/>
                                    <attribute id="MD5" type="LSString" value="abc123"/>
                                    <attribute id="Name" type="LSString" value="Test Mod"/>
                                    <attribute id="UUID" type="guid" value="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"/>
                                    <attribute id="Version64" type="int64" value="36028797018963968"/>
                                </node>
                            </children>
                        </node>
                    </children>
                </node>
            </region>
        </save>
        """
        let url = writeTempFile(name: "modsettings.lsx", content: lsx)
        let result = try service.parseFile(at: url)

        XCTAssertEqual(result.format, .lsx)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.name, "Test Mod")
        XCTAssertEqual(result.sourceName, "modsettings.lsx")
    }

    func testParseLSXFiltersBuiltInUUIDs() throws {
        let builtInUUID = Constants.baseModuleUUID
        let lsx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <save>
            <version major="4" minor="8" revision="0" build="500"/>
            <region id="ModuleSettings">
                <node id="root">
                    <children>
                        <node id="ModOrder">
                            <children>
                                <node id="Module">
                                    <attribute id="UUID" type="guid" value="\(builtInUUID)"/>
                                </node>
                                <node id="Module">
                                    <attribute id="UUID" type="guid" value="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"/>
                                </node>
                            </children>
                        </node>
                        <node id="Mods">
                            <children>
                                <node id="ModuleShortDesc">
                                    <attribute id="Folder" type="LSString" value="GustavX"/>
                                    <attribute id="MD5" type="LSString" value=""/>
                                    <attribute id="Name" type="LSString" value="GustavX"/>
                                    <attribute id="UUID" type="guid" value="\(builtInUUID)"/>
                                    <attribute id="Version64" type="int64" value="36028797018963968"/>
                                </node>
                                <node id="ModuleShortDesc">
                                    <attribute id="Folder" type="LSString" value="RealMod"/>
                                    <attribute id="MD5" type="LSString" value="xyz"/>
                                    <attribute id="Name" type="LSString" value="Real Mod"/>
                                    <attribute id="UUID" type="guid" value="aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"/>
                                    <attribute id="Version64" type="int64" value="36028797018963968"/>
                                </node>
                            </children>
                        </node>
                    </children>
                </node>
            </region>
        </save>
        """
        let url = writeTempFile(name: "modsettings_builtin.lsx", content: lsx)
        let result = try service.parseFile(at: url)

        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.entries.first?.name, "Real Mod")
    }

    // MARK: - ImportError descriptions

    func testImportErrorDescriptions() {
        let invalidJSON = LoadOrderImportService.ImportError.invalidJSON("bad data")
        XCTAssertNotNil(invalidJSON.errorDescription)
        XCTAssertTrue(invalidJSON.errorDescription!.contains("bad data"))

        let unknownFormat = LoadOrderImportService.ImportError.unknownFormat("xyz")
        XCTAssertNotNil(unknownFormat.errorDescription)
        XCTAssertTrue(unknownFormat.errorDescription!.contains("xyz"))

        let emptyList = LoadOrderImportService.ImportError.emptyModList
        XCTAssertNotNil(emptyList.errorDescription)
    }
}
