// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class FilesystemServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FilesystemServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testProfileNamesAreTrimmedAndWhitespaceOnlyNamesAreRejected() throws {
        let service = ProfileService(
            profilesDirectory: temporaryDirectory.appendingPathComponent("Profiles")
        )

        let profile = try service.save(name: "  Testing  ", activeMods: [])
        XCTAssertEqual(profile.name, "Testing")
        XCTAssertThrowsError(try service.save(name: " \n ", activeMods: []))
    }

    func testProfileRenameWritesNewFileBeforeRemovingOldPath() throws {
        let directory = temporaryDirectory.appendingPathComponent("Profiles")
        let service = ProfileService(profilesDirectory: directory)
        let original = try service.save(name: "Original", activeMods: [])

        let renamed = try service.rename(profile: original, to: "Renamed")
        let files = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        XCTAssertEqual(renamed.name, "Renamed")
        XCTAssertEqual(files.count, 1)
        XCTAssertTrue(files[0].lastPathComponent.hasPrefix("Renamed-"))
        XCTAssertEqual(try service.listProfiles().first?.name, "Renamed")
    }

    func testBackupRestoreCreatesSafetyCopyAndReplacesLiveFile() throws {
        let settings = temporaryDirectory.appendingPathComponent("modsettings.lsx")
        let backups = temporaryDirectory.appendingPathComponent("Backups")
        try Data("original".utf8).write(to: settings)
        let service = BackupService(
            modSettingsURL: settings,
            backupsDirectory: backups
        )
        let backup = try service.backupModSettings()
        try Data("changed".utf8).write(to: settings, options: .atomic)

        try service.restore(backup: backup)

        XCTAssertEqual(try String(contentsOf: settings), "original")
        let files = try FileManager.default.contentsOfDirectory(
            at: backups,
            includingPropertiesForKeys: nil
        )
        XCTAssertTrue(files.contains { $0.lastPathComponent.hasPrefix("pre-restore-") })
    }

    func testSavePreferencesHonorEveryConfiguredValue() {
        let suiteName = "SavePreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(false, forKey: AppPreferenceKey.lockModSettingsAfterSave)
        defaults.set(false, forKey: AppPreferenceKey.autoBackupBeforeSave)
        defaults.set(14, forKey: AppPreferenceKey.backupRetentionDays)

        let preferences = SavePreferences(defaults: defaults)

        XCTAssertFalse(preferences.lockAfterSave)
        XCTAssertFalse(preferences.autoBackup)
        XCTAssertEqual(preferences.backupRetentionDays, 14)
    }

    func testFailedPreferencePersistenceRollsBackInMemoryValues() {
        let invalidStorageURL = temporaryDirectory! // A directory cannot be replaced by JSON data.
        let notes = ModNotesService(storageURL: invalidStorageURL)
        let categories = CategoryInferenceService(overridesURL: invalidStorageURL)
        let nexusURLs = NexusURLService(storageURL: invalidStorageURL)

        XCTAssertFalse(notes.setNote("unsaved", for: "uuid"))
        XCTAssertNil(notes.note(for: "uuid"))
        XCTAssertFalse(categories.setOverride(.visual, for: "uuid"))
        XCTAssertNil(categories.override(for: "uuid"))
        XCTAssertFalse(nexusURLs.setURL(
            "https://www.nexusmods.com/baldursgate3/mods/1",
            for: "uuid"
        ))
        XCTAssertNil(nexusURLs.url(for: "uuid"))
    }
}
