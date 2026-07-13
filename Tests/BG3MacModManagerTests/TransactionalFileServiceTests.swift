// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class TransactionalFileServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TransactionalFileServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testSameFileReplacementIsANoOp() throws {
        let file = temporaryDirectory.appendingPathComponent("mod.pak")
        try Data("original".utf8).write(to: file)

        let result = try TransactionalFileService.replaceFiles([
            .init(source: file, destination: file),
        ])

        XCTAssertTrue(result.changedDestinations.isEmpty)
        XCTAssertEqual(try String(contentsOf: file), "original")
    }

    func testSymlinkToSourceIsRecognizedAsSameFile() throws {
        let file = temporaryDirectory.appendingPathComponent("mod.pak")
        let link = temporaryDirectory.appendingPathComponent("alias.pak")
        try Data("original".utf8).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        XCTAssertTrue(TransactionalFileService.identifiesSameFile(file, link))
        let result = try TransactionalFileService.replaceFiles([
            .init(source: link, destination: file),
        ])
        XCTAssertTrue(result.changedDestinations.isEmpty)
        XCTAssertEqual(try String(contentsOf: file), "original")
    }

    func testExistingDestinationIsReplacedAfterStaging() throws {
        let source = temporaryDirectory.appendingPathComponent("source.pak")
        let destination = temporaryDirectory.appendingPathComponent("destination.pak")
        try Data("replacement".utf8).write(to: source)
        try Data("original".utf8).write(to: destination)

        let result = try TransactionalFileService.replaceFiles([
            .init(source: source, destination: destination),
        ])

        XCTAssertEqual(result.changedDestinations, [destination])
        XCTAssertEqual(result.replacedDestinations, [destination])
        XCTAssertEqual(try String(contentsOf: destination), "replacement")
        XCTAssertEqual(try String(contentsOf: source), "replacement")
    }

    func testStagingFailureLeavesEveryDestinationUnchanged() throws {
        let validSource = temporaryDirectory.appendingPathComponent("valid.pak")
        let missingSource = temporaryDirectory.appendingPathComponent("missing.pak")
        let firstDestination = temporaryDirectory.appendingPathComponent("first.pak")
        let secondDestination = temporaryDirectory.appendingPathComponent("second.pak")
        try Data("new".utf8).write(to: validSource)
        try Data("first-original".utf8).write(to: firstDestination)
        try Data("second-original".utf8).write(to: secondDestination)

        XCTAssertThrowsError(try TransactionalFileService.replaceFiles([
            .init(source: validSource, destination: firstDestination),
            .init(source: missingSource, destination: secondDestination),
        ]))

        XCTAssertEqual(try String(contentsOf: firstDestination), "first-original")
        XCTAssertEqual(try String(contentsOf: secondDestination), "second-original")
    }
}
