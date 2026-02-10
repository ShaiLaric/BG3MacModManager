import XCTest
@testable import BG3MacModManager

final class Version64Tests: XCTestCase {

    func testEncodeVersion_1_0_0_0() {
        let version = Version64(major: 1, minor: 0, revision: 0, build: 0)
        XCTAssertEqual(version.rawValue, 36028797018963968)
    }

    func testDecodeVersion_1_0_0_0() {
        let version = Version64(rawValue: 36028797018963968)
        XCTAssertEqual(version.major, 1)
        XCTAssertEqual(version.minor, 0)
        XCTAssertEqual(version.revision, 0)
        XCTAssertEqual(version.build, 0)
    }

    func testRoundTrip() {
        let original = Version64(major: 4, minor: 7, revision: 1, build: 3)
        let decoded = Version64(rawValue: original.rawValue)
        XCTAssertEqual(original, decoded)
    }

    func testDescription() {
        let version = Version64(major: 2, minor: 3, revision: 4, build: 5)
        XCTAssertEqual(version.description, "2.3.4.5")
    }

    func testParseVersionString() {
        let version = Version64(versionString: "1.2.3.4")
        XCTAssertNotNil(version)
        XCTAssertEqual(version?.major, 1)
        XCTAssertEqual(version?.minor, 2)
        XCTAssertEqual(version?.revision, 3)
        XCTAssertEqual(version?.build, 4)
    }

    func testParseRawString() {
        let version = Version64(rawString: "36028797018963968")
        XCTAssertNotNil(version)
        XCTAssertEqual(version?.major, 1)
        XCTAssertEqual(version?.minor, 0)
    }

    func testComparable() {
        let v1 = Version64(major: 1, minor: 0, revision: 0, build: 0)
        let v2 = Version64(major: 2, minor: 0, revision: 0, build: 0)
        XCTAssertTrue(v1 < v2)
    }

    func testPartialVersionString() {
        let v1 = Version64(versionString: "1")
        XCTAssertNotNil(v1)
        XCTAssertEqual(v1?.major, 1)
        XCTAssertEqual(v1?.minor, 0)

        let v2 = Version64(versionString: "1.2")
        XCTAssertNotNil(v2)
        XCTAssertEqual(v2?.major, 1)
        XCTAssertEqual(v2?.minor, 2)
        XCTAssertEqual(v2?.revision, 0)
    }
}
