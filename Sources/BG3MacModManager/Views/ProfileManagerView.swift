// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

/// View for managing saved mod profiles (named load order configurations).
struct ProfileManagerView: View {
    @EnvironmentObject var appState: AppState
    @State private var newProfileName = ""
    @State private var showingSaveSheet = false
    @State private var showingImportDialog = false
    @State private var renamingProfile: ModProfile?
    @State private var renameText = ""
    @State private var showUpdateConfirmation = false
    @State private var profileToUpdate: ModProfile?
    @FocusState private var isRenameFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Mod Profiles")
                    .font(.title2.bold())
                Spacer()
                Button("Save Current...") {
                    showingSaveSheet = true
                }
                .help("Save current mod configuration as a profile")
                Button {
                    importProfile()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .help("Import a profile from a JSON file")

                Menu {
                    Button("CSV (.csv)") { exportCurrentLoadOrder(format: .csv) }
                    Button("Markdown (.md)") { exportCurrentLoadOrder(format: .markdown) }
                    Button("Plain Text (.txt)") { exportCurrentLoadOrder(format: .plainText) }
                } label: {
                    Label("Export List", systemImage: "doc.text")
                }
                .help("Export current load order as text")
                .disabled(appState.activeMods.isEmpty)

                Button {
                    appState.exportLoadOrderToZip()
                } label: {
                    Label("Export ZIP", systemImage: "archivebox")
                }
                .help("Export all active mod PAK files and settings as a ZIP archive")
                .disabled(appState.activeMods.isEmpty || appState.isExporting)
            }
            .padding()

            Divider()

            if appState.profiles.isEmpty {
                emptyState
            } else {
                profileList
            }
        }
        .sheet(isPresented: $showingSaveSheet) {
            saveProfileSheet
        }
    }

    // MARK: - Profile List

    private var profileList: some View {
        List {
            ForEach(appState.profiles) { profile in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if renamingProfile?.id == profile.id {
                            TextField("Profile Name", text: $renameText)
                                .textFieldStyle(.roundedBorder)
                                .focused($isRenameFieldFocused)
                                .onSubmit { commitRename(profile) }
                                .onExitCommand {
                                    renamingProfile = nil
                                    renameText = ""
                                }
                        } else {
                            Text(profile.name)
                                .font(.headline)
                        }
                        Text("\(profile.activeModUUIDs.count) mods")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Saved \(profile.updatedAt, style: .relative) ago")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Button("Load") {
                        Task { await appState.loadProfile(profile) }
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Apply this profile's mod configuration")

                    Button {
                        profileToUpdate = profile
                        showUpdateConfirmation = true
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .help("Overwrite this profile with the current load order")

                    Button {
                        renamingProfile = profile
                        renameText = profile.name
                        isRenameFieldFocused = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .help("Rename this profile")

                    Button {
                        exportProfile(profile)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Export profile")

                    Button(role: .destructive) {
                        Task { await appState.deleteProfile(profile) }
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete profile")
                }
                .padding(.vertical, 4)
            }
        }
        .confirmationDialog(
            "Update Profile?",
            isPresented: $showUpdateConfirmation,
            titleVisibility: .visible
        ) {
            Button("Update") {
                if let profile = profileToUpdate {
                    Task { await appState.updateProfile(profile) }
                }
                profileToUpdate = nil
            }
            Button("Cancel", role: .cancel) {
                profileToUpdate = nil
            }
        } message: {
            if let profile = profileToUpdate {
                Text("This will overwrite \"\(profile.name)\" with your current \(appState.activeMods.count) active mods and their load order. This cannot be undone.")
            }
        }
    }

    private func commitRename(_ profile: ModProfile) {
        let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newName.isEmpty else {
            renamingProfile = nil
            renameText = ""
            return
        }
        Task {
            await appState.renameProfile(profile, to: newName)
            renamingProfile = nil
            renameText = ""
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No Saved Profiles")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Save your current mod configuration as a profile to quickly switch between setups.")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 350)
            Button("Save Current Configuration...") {
                showingSaveSheet = true
            }
            .buttonStyle(.borderedProminent)
            .help("Save current mod configuration as a profile")
            Spacer()
        }
    }

    // MARK: - Save Sheet

    private var saveProfileSheet: some View {
        VStack(spacing: 16) {
            Text("Save Profile")
                .font(.headline)

            TextField("Profile Name", text: $newProfileName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)

            Text("This will save your current \(appState.activeMods.count) active mods and their load order.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Cancel") {
                    showingSaveSheet = false
                    newProfileName = ""
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    Task {
                        await appState.saveProfile(name: newProfileName)
                        showingSaveSheet = false
                        newProfileName = ""
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newProfileName.isEmpty)
            }
        }
        .padding(24)
    }

    // MARK: - Import / Export

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.title = "Import Profile"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                do {
                    _ = try appState.profileService.importProfile(from: url)
                    await appState.refreshProfiles()
                } catch {
                    appState.errorMessage = error.localizedDescription
                    appState.showError = true
                }
            }
        }
    }

    private func exportCurrentLoadOrder(format: TextExportService.ExportFormat) {
        let content = appState.textExportService.export(
            activeMods: appState.activeMods,
            format: format
        )
        let panel = NSSavePanel()
        panel.title = "Export Load Order"
        panel.nameFieldStringValue = "load-order.\(format.fileExtension)"
        if let contentType = UTType(filenameExtension: format.fileExtension) {
            panel.allowedContentTypes = [contentType]
        }

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                appState.errorMessage = error.localizedDescription
                appState.showError = true
            }
        }
    }

    private func exportProfile(_ profile: ModProfile) {
        let panel = NSSavePanel()
        panel.title = "Export Profile"
        panel.nameFieldStringValue = "\(profile.name).json"
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try appState.profileService.export(profile: profile, to: url)
            } catch {
                appState.errorMessage = error.localizedDescription
                appState.showError = true
            }
        }
    }
}
