// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import BG3MacModManager

final class LocationSettingsTests: XCTestCase {

    private let keys = [
        AppPreferenceKey.larianDocumentsPath,
        AppPreferenceKey.steamAppsPath,
        AppPreferenceKey.appSupportDirectoryPath,
    ]
    private var savedValues: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        for key in keys {
            savedValues[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            if let value = savedValues[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    // MARK: - FileLocations overrides

    func testUnsetOverridesUseDefaults() {
        XCTAssertEqual(FileLocations.larianDocuments.path, FileLocations.defaultLarianDocuments.standardizedFileURL.path)
        XCTAssertEqual(FileLocations.steamApps.path, FileLocations.defaultSteamApps.standardizedFileURL.path)
        XCTAssertEqual(FileLocations.appSupportDirectory.path, FileLocations.defaultAppSupportDirectory.standardizedFileURL.path)
    }

    func testEmptyOverridesUseDefaults() {
        for key in keys {
            UserDefaults.standard.set("", forKey: key)
        }
        XCTAssertEqual(FileLocations.larianDocuments.path, FileLocations.defaultLarianDocuments.standardizedFileURL.path)
        XCTAssertEqual(FileLocations.steamApps.path, FileLocations.defaultSteamApps.standardizedFileURL.path)
        XCTAssertEqual(FileLocations.appSupportDirectory.path, FileLocations.defaultAppSupportDirectory.standardizedFileURL.path)
    }

    func testLarianOverrideMovesDerivedPaths() {
        UserDefaults.standard.set("/Volumes/Games/Baldur's Gate 3", forKey: AppPreferenceKey.larianDocumentsPath)

        XCTAssertEqual(FileLocations.modsFolder.path, "/Volumes/Games/Baldur's Gate 3/Mods")
        XCTAssertEqual(
            FileLocations.modSettingsFile.path,
            "/Volumes/Games/Baldur's Gate 3/PlayerProfiles/Public/modsettings.lsx"
        )
    }

    func testSteamOverrideMovesGameInstallation() {
        UserDefaults.standard.set("/Volumes/Games/steamapps", forKey: AppPreferenceKey.steamAppsPath)

        XCTAssertEqual(FileLocations.gameInstallation.path, "/Volumes/Games/steamapps/common/Baldurs Gate 3")
    }

    func testAppSupportOverrideMovesAppData() {
        UserDefaults.standard.set("/Volumes/Games/BG3MacModManager", forKey: AppPreferenceKey.appSupportDirectoryPath)

        XCTAssertEqual(FileLocations.backupsDirectory.path, "/Volumes/Games/BG3MacModManager/Backups")
        XCTAssertEqual(FileLocations.lastExportHashFile.path, "/Volumes/Games/BG3MacModManager/last_export_hash")
    }

    func testOverridePathsAreStandardized() {
        UserDefaults.standard.set("/Volumes/Games/./BG3/../Baldur's Gate 3", forKey: AppPreferenceKey.larianDocumentsPath)

        XCTAssertEqual(FileLocations.larianDocuments.path, "/Volumes/Games/Baldur's Gate 3")
    }

    func testDefaultModSettingsFileIgnoresOverride() {
        // Paths are compared because that is what the external-change check compares.
        let defaultFile = FileLocations.modSettingsFile.path
        XCTAssertEqual(FileLocations.defaultModSettingsFile.path, defaultFile)

        UserDefaults.standard.set("/Volumes/Games/Baldur's Gate 3", forKey: AppPreferenceKey.larianDocumentsPath)

        XCTAssertEqual(FileLocations.defaultModSettingsFile.path, defaultFile)
        XCTAssertNotEqual(FileLocations.modSettingsFile.path, defaultFile)
    }

    // MARK: - Busy gating

    @MainActor
    func testLocationsCanChangeWhenIdle() {
        let state = AppState()
        clearBusyFlags(state)
        XCTAssertTrue(state.canChangeLocations)
    }

    @MainActor
    func testLocationsCannotChangeDuringFileOperations() {
        let flags: [(String, ReferenceWritableKeyPath<AppState, Bool>)] = [
            ("isLoading", \.isLoading),
            ("isImporting", \.isImporting),
            ("isExporting", \.isExporting),
            ("isUpdatingMod", \.isUpdatingMod),
            ("isCheckingForUpdates", \.isCheckingForUpdates),
            ("isScanningSaveGames", \.isScanningSaveGames),
            ("isCheckingReadiness", \.isCheckingReadiness),
        ]
        let state = AppState()

        for (name, flag) in flags {
            clearBusyFlags(state)
            state[keyPath: flag] = true
            XCTAssertFalse(state.canChangeLocations, "\(name) should block location changes")
        }
    }

    @MainActor
    private func clearBusyFlags(_ state: AppState) {
        state.isLoading = false
        state.isImporting = false
        state.isExporting = false
        state.isUpdatingMod = false
        state.isCheckingForUpdates = false
        state.isScanningSaveGames = false
        state.isCheckingReadiness = false
    }
}
