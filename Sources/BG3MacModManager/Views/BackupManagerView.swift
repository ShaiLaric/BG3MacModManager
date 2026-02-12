import SwiftUI

/// View for managing modsettings.lsx backups.
struct BackupManagerView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingRestoreConfirmation = false
    @State private var selectedBackup: BackupService.Backup?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Backups")
                    .font(.title2.bold())
                Spacer()
                Button {
                    createBackup()
                } label: {
                    Label("Create Backup", systemImage: "plus")
                }
                .help("Create a backup of modsettings.lsx")
            }
            .padding()

            Divider()

            if appState.backups.isEmpty {
                emptyState
            } else {
                backupList
            }
        }
        .confirmationDialog(
            "Restore Backup?",
            isPresented: $showingRestoreConfirmation,
            presenting: selectedBackup
        ) { backup in
            Button("Restore", role: .destructive) {
                Task { await appState.restoreBackup(backup) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { backup in
            Text("This will replace your current modsettings.lsx with the backup from \(backup.displayName). A safety backup will be created first.")
        }
    }

    private var backupList: some View {
        List {
            ForEach(appState.backups) { backup in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(backup.displayName)
                            .font(.headline)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(backup.fileSize), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Restore") {
                        selectedBackup = backup
                        showingRestoreConfirmation = true
                    }
                    .help("Restore modsettings.lsx from this backup")

                    Button(role: .destructive) {
                        Task { await appState.deleteBackup(backup) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete this backup")
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Backups")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Backups are created automatically when you save mod settings. You can also create manual backups.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
            Button("Create Backup Now") {
                createBackup()
            }
            .buttonStyle(.borderedProminent)
            .help("Create a backup of modsettings.lsx")
            Spacer()
        }
    }

    private func createBackup() {
        do {
            try appState.backupService.backupModSettings()
            Task { await appState.refreshBackups() }
            appState.statusMessage = "Backup created"
        } catch {
            appState.errorMessage = error.localizedDescription
            appState.showError = true
        }
    }
}
