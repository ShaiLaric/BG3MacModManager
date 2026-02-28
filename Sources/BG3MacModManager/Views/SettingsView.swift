// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// App settings view (shown in Preferences window).
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("lockModSettingsAfterSave") var lockAfterSave = true
    @AppStorage("autoBackupBeforeSave") var autoBackup = true
    @AppStorage("backupRetentionDays") var backupRetentionDays = 30
    @AppStorage("autoSaveBeforeLaunch") var autoSaveBeforeLaunch = false
    @AppStorage("autoSaveOnProfileLoad") var autoSaveOnProfileLoad = false
    @AppStorage("nexusAPIKey") var nexusAPIKey = ""
    @AppStorage("autoCheckNexusUpdates") var autoCheckNexusUpdates = false

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gear") }

            pathSettings
                .tabItem { Label("Paths", systemImage: "folder") }

            seSettings
                .tabItem { Label("Script Extender", systemImage: "terminal") }
        }
        .frame(width: 500, height: 420)
        .padding()
    }

    // MARK: - General

    private var generalSettings: some View {
        Form {
            GroupBox("Saving") {
                Toggle("Lock modsettings.lsx after saving", isOn: $lockAfterSave)
                    .help("Prevents the game from overwriting your mod configuration")

                Toggle("Auto-backup before saving", isOn: $autoBackup)
                    .help("Creates a backup of modsettings.lsx before any changes")

                Divider()

                Toggle("Auto-save before launching game", isOn: $autoSaveBeforeLaunch)
                    .help("Automatically save your load order to modsettings.lsx before launching the game")

                Toggle("Auto-save when loading a profile", isOn: $autoSaveOnProfileLoad)
                    .help("Automatically save your load order to modsettings.lsx after loading a profile")
            }

            GroupBox("Backups") {
                Picker("Keep backups for", selection: $backupRetentionDays) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Forever").tag(0)
                }
                .help("How long to keep automatic backups before cleanup")

                Button("Clean Old Backups") {
                    guard backupRetentionDays > 0 else { return }
                    try? appState.backupService.pruneBackups(olderThanDays: backupRetentionDays)
                    Task { await appState.refreshBackups() }
                }
                .help("Delete backups older than the retention period")
            }

            GroupBox("Game") {
                HStack {
                    Text("Game Status:")
                    Text(appState.isGameInstalled ? "Installed" : "Not Found")
                        .foregroundStyle(appState.isGameInstalled ? .green : .red)
                        .help(appState.isGameInstalled
                            ? "Baldur's Gate 3 detected via Steam"
                            : "Baldur's Gate 3 not found — check that it's installed via Steam")
                }
            }

            GroupBox("Nexus Mods") {
                SecureField("API Key", text: $nexusAPIKey)
                    .help("Your personal Nexus Mods API key for checking mod updates")

                Text("Your API key is stored locally and only used to query the Nexus Mods API for version information. It is never shared.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)

                if nexusAPIKey.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text("An API key is required to check for mod updates.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Get API Key from Nexus Mods") {
                        if let url = URL(string: "https://www.nexusmods.com/users/myaccount?tab=api+access") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Opens your Nexus Mods account page where you can generate a personal API key")
                }

                Toggle("Check for updates on app launch", isOn: $autoCheckNexusUpdates)
                    .help("Automatically check Nexus Mods for updates when the app starts. Requires an API key and Nexus URLs set on your mods.")
                    .disabled(nexusAPIKey.isEmpty)
            }
        }
    }

    // MARK: - Paths

    private var pathSettings: some View {
        Form {
            Section("Detected Paths") {
                pathRow("Mods Folder", FileLocations.modsFolder, exists: FileLocations.modsFolderExists)
                pathRow("modsettings.lsx", FileLocations.modSettingsFile, exists: FileLocations.modSettingsExists)
                pathRow("Game App", FileLocations.gameApp, exists: FileLocations.isGameInstalled)
                pathRow("SE Dylib", FileLocations.seDeployedDylib,
                        exists: FileManager.default.fileExists(atPath: FileLocations.seDeployedDylib.path))
            }

            Section("App Data") {
                pathRow("Profiles", FileLocations.profilesDirectory, exists: true)
                pathRow("Backups", FileLocations.backupsDirectory, exists: true)
            }
        }
    }

    private func pathRow(_ label: String, _ url: URL, exists: Bool) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(label)
                    .font(.body)
                Text(url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            Image(systemName: exists ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(exists ? .green : .red)
                .help(exists ? "Found at this path" : "Not found at this path")
        }
    }

    // MARK: - Script Extender

    private var seSettings: some View {
        Form {
            if let status = appState.seStatus {
                Section("Status") {
                    HStack {
                        Text("Installed:")
                        Text(status.isInstalled ? "Yes" : "No")
                            .foregroundStyle(status.isInstalled ? .green : .red)
                    }
                    HStack {
                        Text("Deployed:")
                        Text(status.isDeployed ? "Yes" : "No")
                            .foregroundStyle(status.isDeployed ? .green : .red)
                    }
                }

                if status.isInstalled {
                    Section("Debug Options") {
                        Text("These environment variables can be set via the bg3w.sh launch script.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(ScriptExtenderService.SEEnvironmentVar.allCases, id: \.rawValue) { envVar in
                            HStack {
                                Text(envVar.rawValue)
                                    .font(.body.monospaced())
                                Spacer()
                                Text(envVar.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Text("Loading...")
            }
        }
    }
}
