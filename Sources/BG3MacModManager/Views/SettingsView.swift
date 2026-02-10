import SwiftUI

/// App settings view (shown in Preferences window).
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("lockModSettingsAfterSave") var lockAfterSave = true
    @AppStorage("autoBackupBeforeSave") var autoBackup = true
    @AppStorage("backupRetentionDays") var backupRetentionDays = 30

    var body: some View {
        TabView {
            generalSettings
                .tabItem { Label("General", systemImage: "gear") }

            pathSettings
                .tabItem { Label("Paths", systemImage: "folder") }

            seSettings
                .tabItem { Label("Script Extender", systemImage: "terminal") }
        }
        .frame(width: 500, height: 350)
        .padding()
    }

    // MARK: - General

    private var generalSettings: some View {
        Form {
            Section("Saving") {
                Toggle("Lock modsettings.lsx after saving", isOn: $lockAfterSave)
                    .help("Prevents the game from overwriting your mod configuration")

                Toggle("Auto-backup before saving", isOn: $autoBackup)
                    .help("Creates a backup of modsettings.lsx before any changes")
            }

            Section("Backups") {
                Picker("Keep backups for", selection: $backupRetentionDays) {
                    Text("7 days").tag(7)
                    Text("14 days").tag(14)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Forever").tag(0)
                }

                Button("Clean Old Backups") {
                    guard backupRetentionDays > 0 else { return }
                    try? appState.backupService.pruneBackups(olderThanDays: backupRetentionDays)
                    Task { await appState.refreshBackups() }
                }
                .help("Delete backups older than the retention period")
            }

            Section("Game") {
                HStack {
                    Text("Game Status:")
                    Text(appState.isGameInstalled ? "Installed" : "Not Found")
                        .foregroundStyle(appState.isGameInstalled ? .green : .red)
                }
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
