// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class DataBinaryReadingTests: XCTestCase {

    // MARK: - readUInt16

    func testReadUInt16LittleEndian() {
        let data = Data([0x01, 0x00])
        XCTAssertEqual(data.readUInt16(at: 0), 1)
    }

    func testReadUInt16AtOffset() {
        let data = Data([0xFF, 0xFF, 0x34, 0x12])
        XCTAssertEqual(data.readUInt16(at: 2), 0x1234)
    }

    func testReadUInt16OutOfBounds() {
        let data = Data([0x01])
        XCTAssertEqual(data.readUInt16(at: 0), 0)
    }

    // MARK: - readUInt32

    func testReadUInt32LittleEndian() {
        let data = Data([0x01, 0x00, 0x00, 0x00])
        XCTAssertEqual(data.readUInt32(at: 0), 1)
    }

    func testReadUInt32KnownValue() {
        // 1234 = 0x000004D2, little-endian: D2 04 00 00
        let data = Data([0xD2, 0x04, 0x00, 0x00])
        XCTAssertEqual(data.readUInt32(at: 0), 1234)
    }

    func testReadUInt32OutOfBounds() {
        let data = Data([0x01, 0x02])
        XCTAssertEqual(data.readUInt32(at: 0), 0)
    }

    // MARK: - readUInt64

    func testReadUInt64LittleEndian() {
        let data = Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(data.readUInt64(at: 0), 1)
    }

    func testReadUInt64KnownValue() {
        // 36028797018963968 = 0x0080000000000000
        // little-endian: 00 00 00 00 00 00 80 00
        let data = Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00])
        XCTAssertEqual(data.readUInt64(at: 0), 36028797018963968)
    }

    func testReadUInt64OutOfBounds() {
        let data = Data([0x01, 0x02, 0x03])
        XCTAssertEqual(data.readUInt64(at: 0), 0)
    }

    // MARK: - readInt64

    func testReadInt64LittleEndian() {
        let data = Data([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(data.readInt64(at: 0), 1)
    }

    func testReadInt64NegativeValue() {
        // -1 in two's complement = 0xFFFFFFFFFFFFFFFF
        let data = Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        XCTAssertEqual(data.readInt64(at: 0), -1)
    }

    func testReadInt64OutOfBounds() {
        let data = Data()
        XCTAssertEqual(data.readInt64(at: 0), 0)
    }
}
