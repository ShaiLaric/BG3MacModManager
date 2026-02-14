// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Central registry of all BG3-related file paths on macOS.
enum FileLocations {

    // MARK: - Larian Documents Root

    static var larianDocuments: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Larian Studios/Baldur's Gate 3")
    }

    // MARK: - Mods

    /// `~/Documents/Larian Studios/Baldur's Gate 3/Mods/`
    static var modsFolder: URL {
        larianDocuments.appendingPathComponent("Mods")
    }

    // MARK: - Player Profiles

    /// `~/Documents/Larian Studios/Baldur's Gate 3/PlayerProfiles/Public/`
    static var publicProfile: URL {
        larianDocuments.appendingPathComponent("PlayerProfiles/Public")
    }

    /// `~/Documents/Larian Studios/Baldur's Gate 3/PlayerProfiles/Public/modsettings.lsx`
    static var modSettingsFile: URL {
        publicProfile.appendingPathComponent("modsettings.lsx")
    }

    /// `~/Documents/Larian Studios/Baldur's Gate 3/PlayerProfiles/Public/Savegames/Story/`
    static var savegamesFolder: URL {
        publicProfile.appendingPathComponent("Savegames/Story")
    }

    /// `~/Documents/Larian Studios/Baldur's Gate 3/ModCrashSanityCheck/`
    /// Since Patch 8, this directory causes the game to deactivate externally-managed mods.
    static var modCrashSanityCheckFolder: URL {
        larianDocuments.appendingPathComponent("ModCrashSanityCheck")
    }

    // MARK: - Game Installation (Steam)

    static var steamApps: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Steam/steamapps")
    }

    /// `~/Library/Application Support/Steam/steamapps/common/Baldurs Gate 3/`
    static var gameInstallation: URL {
        steamApps.appendingPathComponent("common/Baldurs Gate 3")
    }

    /// `~/Library/Application Support/Steam/steamapps/common/Baldurs Gate 3/Data/`
    static var gameData: URL {
        gameInstallation.appendingPathComponent("Data")
    }

    /// `~/Library/Application Support/Steam/steamapps/common/Baldurs Gate 3/Baldur's Gate 3.app`
    static var gameApp: URL {
        gameInstallation.appendingPathComponent("Baldur's Gate 3.app")
    }

    static var gameExecutable: URL {
        gameApp.appendingPathComponent("Contents/MacOS")
    }

    // MARK: - Script Extender (bg3se-macos)

    /// Expected location of deployed SE dylib inside the game app bundle.
    static var seDeployedDylib: URL {
        gameExecutable.appendingPathComponent("libbg3se.dylib")
    }

    /// `~/Library/Application Support/BG3SE/`
    static var seDataDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/BG3SE")
    }

    /// `~/Library/Application Support/BG3SE/logs/`
    static var seLogsDirectory: URL {
        seDataDirectory.appendingPathComponent("logs")
    }

    static var seLatestLog: URL {
        seLogsDirectory.appendingPathComponent("latest.log")
    }

    // MARK: - App Data

    static var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("BG3MacModManager")
    }

    static var backupsDirectory: URL {
        appSupportDirectory.appendingPathComponent("Backups")
    }

    static var profilesDirectory: URL {
        appSupportDirectory.appendingPathComponent("Profiles")
    }

    /// Stores a SHA-256 hash of modsettings.lsx as it was last written by this app.
    static var lastExportHashFile: URL {
        appSupportDirectory.appendingPathComponent("last_export_hash")
    }

    /// Persists whether Script Extender was previously detected as deployed.
    static var seDeployedFlagFile: URL {
        appSupportDirectory.appendingPathComponent("se_was_deployed.json")
    }

    // MARK: - Helpers

    /// Ensures a directory exists, creating it if necessary.
    static func ensureDirectoryExists(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    /// Returns true if the game appears to be installed.
    static var isGameInstalled: Bool {
        FileManager.default.fileExists(atPath: gameApp.path)
    }

    /// Returns true if the Mods folder exists.
    static var modsFolderExists: Bool {
        FileManager.default.fileExists(atPath: modsFolder.path)
    }

    /// Returns true if modsettings.lsx exists.
    static var modSettingsExists: Bool {
        FileManager.default.fileExists(atPath: modSettingsFile.path)
    }

    /// Returns true if the ModCrashSanityCheck directory exists.
    static var modCrashSanityCheckExists: Bool {
        FileManager.default.fileExists(atPath: modCrashSanityCheckFolder.path)
    }
}
