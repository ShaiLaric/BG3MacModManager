// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Launches Baldur's Gate 3 via Steam with optional Script Extender support.
final class GameLaunchService {

    private let seService = ScriptExtenderService()

    struct LaunchOptions {
        var useScriptExtender: Bool = true
        var seNoHooks: Bool = false
        var seNoNet: Bool = false
        var seMinimal: Bool = false
    }

    /// Launch BG3 through Steam.
    ///
    /// On macOS, we use `open steam://run/<appId>` which tells Steam to launch the game.
    /// If Script Extender is needed, the user must have Steam launch options configured
    /// to point to the bg3w.sh wrapper script.
    func launchGame(options: LaunchOptions = LaunchOptions()) throws {
        // Use Steam's URL protocol to launch the game
        let steamURL = URL(string: "steam://run/\(Constants.steamAppID)")!

        let workspace = NSWorkspace.shared
        workspace.open(steamURL)
    }

    /// Check if Steam is running.
    func isSteamRunning() -> Bool {
        let workspace = NSWorkspace.shared
        return workspace.runningApplications.contains { app in
            app.bundleIdentifier == "com.valvesoftware.steam"
        }
    }

    /// Check if BG3 is currently running.
    func isGameRunning() -> Bool {
        let workspace = NSWorkspace.shared
        return workspace.runningApplications.contains { app in
            app.localizedName?.contains("Baldur's Gate 3") == true ||
            app.bundleIdentifier?.contains("baldursgate3") == true ||
            app.bundleIdentifier?.contains("larianstudios") == true
        }
    }

    /// Open the game's Mods folder in Finder.
    func openModsFolder() {
        let url = FileLocations.modsFolder
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.open(url)
    }

    /// Open modsettings.lsx in the default text editor.
    func openModSettings() {
        let url = FileLocations.modSettingsFile
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Open SE logs folder in Finder.
    func openSELogs() {
        let url = FileLocations.seLogsDirectory
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.open(url)
    }
}

// Needed for NSWorkspace on macOS
import AppKit
