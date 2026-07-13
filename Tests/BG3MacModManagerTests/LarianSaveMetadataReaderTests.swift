// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import XCTest
@testable import BG3MacModManager

final class LarianSaveMetadataReaderTests: XCTestCase {
    func testReadsGameIDAndExplicitModOrder() throws {
        let first = SaveModEntry(
            uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            name: "First",
            folder: "FirstFolder",
            version64: 100,
            md5: "first-md5"
        )
        let second = SaveModEntry(
            uuid: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
            name: "Second",
            folder: "SecondFolder",
            version64: 200,
            md5: "second-md5"
        )
        let data = try makeTestSaveMetadataLSF(
            gameID: "campaign-game-id",
            mods: [first, second],
            order: [second.uuid, first.uuid]
        )

        let result = try LarianSaveMetadataReader().read(data: data)

        XCTAssertEqual(result.gameID, "campaign-game-id")
        XCTAssertEqual(result.mods, [second, first])
    }

    func testReadsLZ4CompressedModernMetadata() throws {
        let mod = SaveModEntry(
            uuid: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            name: "Compressed",
            folder: "CompressedFolder",
            version64: 300,
            md5: "compressed-md5"
        )
        let data = try makeTestSaveMetadataLSF(
            gameID: "compressed-game-id",
            mods: [mod],
            order: [mod.uuid],
            compressSections: true
        )

        let result = try LarianSaveMetadataReader().read(data: data)

        XCTAssertEqual(result.gameID, "compressed-game-id")
        XCTAssertEqual(result.mods, [mod])
    }

    func testRejectsInvalidSignature() {
        XCTAssertThrowsError(try LarianSaveMetadataReader().read(data: Data("NOPE".utf8))) { error in
            guard case LarianSaveMetadataReader.ReaderError.invalidSignature = error else {
                XCTFail("Expected invalidSignature, got \(error)")
                return
            }
        }
    }

    func testRejectsSectionAboveConfiguredLimit() {
        var data = Data("LSOF".utf8)
        data.append(littleEndian(UInt32(7)))
        data.append(littleEndian(UInt64(0)))
        data.append(littleEndian(UInt32(1_025)))
        data.append(Data(count: 44))
        let limits = LarianSaveMetadataReader.Limits(
            maximumSectionBytes: 1_024,
            maximumTotalExpandedBytes: 4_096,
            maximumNames: 100,
            maximumNodes: 100,
            maximumAttributes: 100
        )

        XCTAssertThrowsError(try LarianSaveMetadataReader().read(data: data, limits: limits)) { error in
            guard case LarianSaveMetadataReader.ReaderError.limitExceeded = error else {
                XCTFail("Expected limitExceeded, got \(error)")
                return
            }
        }
    }

    private func littleEndian<T: FixedWidthInteger>(_ value: T) -> Data {
        var value = value.littleEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
}
