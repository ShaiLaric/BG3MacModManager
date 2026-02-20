// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class ModNotesServiceTests: XCTestCase {

    var service: ModNotesService!
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModNotesTests-\(UUID().uuidString).json")
        service = ModNotesService(storageURL: tempURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempURL)
        super.tearDown()
    }

    func testNoteForUnknownUUIDReturnsNil() {
        XCTAssertNil(service.note(for: "nonexistent-uuid"))
    }

    func testSetAndGetNote() {
        service.setNote("Test note", for: "test-uuid")
        XCTAssertEqual(service.note(for: "test-uuid"), "Test note")
    }

    func testSetNilClearsNote() {
        service.setNote("Test note", for: "test-uuid")
        service.setNote(nil, for: "test-uuid")
        XCTAssertNil(service.note(for: "test-uuid"))
    }

    func testSetEmptyStringClearsNote() {
        service.setNote("Test note", for: "test-uuid")
        service.setNote("", for: "test-uuid")
        XCTAssertNil(service.note(for: "test-uuid"))
    }

    func testWhitespaceOnlyNoteIsCleared() {
        service.setNote("   \n  ", for: "test-uuid")
        XCTAssertNil(service.note(for: "test-uuid"))
    }

    func testAllNotesReturnsAllStoredNotes() {
        service.setNote("Note A", for: "uuid-a")
        service.setNote("Note B", for: "uuid-b")
        let all = service.allNotes()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(all["uuid-a"], "Note A")
        XCTAssertEqual(all["uuid-b"], "Note B")
    }

    func testOverwriteExistingNote() {
        service.setNote("Original", for: "test-uuid")
        service.setNote("Updated", for: "test-uuid")
        XCTAssertEqual(service.note(for: "test-uuid"), "Updated")
    }

    func testAllNotesEmptyByDefault() {
        XCTAssertTrue(service.allNotes().isEmpty)
    }

    func testClearOneNoteDoesNotAffectOthers() {
        service.setNote("Note A", for: "uuid-a")
        service.setNote("Note B", for: "uuid-b")
        service.setNote(nil, for: "uuid-a")
        XCTAssertNil(service.note(for: "uuid-a"))
        XCTAssertEqual(service.note(for: "uuid-b"), "Note B")
    }

    // MARK: - Persistence Round-Trip

    func testNotesPersistAcrossInstances() {
        service.setNote("Persisted note", for: "persist-uuid")

        // Create a second instance reading from the same file
        let service2 = ModNotesService(storageURL: tempURL)
        XCTAssertEqual(service2.note(for: "persist-uuid"), "Persisted note")
    }
}
