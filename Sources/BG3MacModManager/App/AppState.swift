import SwiftUI
import Combine

/// Central observable state for the entire application.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Published State

    /// Mods currently in the active load order.
    @Published var activeMods: [ModInfo] = []

    /// Mods discovered but not in the active load order.
    @Published var inactiveMods: [ModInfo] = []

    /// Currently selected mod (for detail panel).
    @Published var selectedModID: String?

    /// Saved profiles.
    @Published var profiles: [ModProfile] = []

    /// Script Extender status.
    @Published var seStatus: ScriptExtenderService.SEStatus?

    /// Backup list.
    @Published var backups: [BackupService.Backup] = []

    /// Whether the game is detected as installed.
    @Published var isGameInstalled: Bool = false

    /// Status / error messages.
    @Published var statusMessage: String = ""
    @Published var errorMessage: String?
    @Published var showError: Bool = false

    /// Loading state.
    @Published var isLoading: Bool = false

    // MARK: - Services

    let modSettingsService = ModSettingsService()
    let discoveryService = ModDiscoveryService()
    let profileService = ProfileService()
    let backupService = BackupService()
    let seService = ScriptExtenderService()
    let launchService = GameLaunchService()

    // MARK: - Initialization

    init() {
        isGameInstalled = FileLocations.isGameInstalled
    }

    func initialLoad() {
        Task {
            await refreshAll()
        }
    }

    // MARK: - Refresh

    func refreshAll() async {
        isLoading = true
        defer { isLoading = false }

        await refreshMods()
        await refreshProfiles()
        await refreshBackups()
        refreshSEStatus()
    }

    func refreshMods() async {
        do {
            let result = try discoveryService.discoverModsWithState()
            activeMods = result.active
            inactiveMods = result.inactive
            statusMessage = "Found \(activeMods.count) active, \(inactiveMods.count) inactive mods"
        } catch {
            showError(error)
        }
    }

    func refreshProfiles() async {
        do {
            profiles = try profileService.listProfiles()
        } catch {
            showError(error)
        }
    }

    func refreshBackups() async {
        do {
            backups = try backupService.listBackups()
        } catch {
            showError(error)
        }
    }

    func refreshSEStatus() {
        seStatus = seService.checkStatus()
    }

    // MARK: - Mod Management

    /// Activate a mod (move from inactive to active).
    func activateMod(_ mod: ModInfo) {
        guard let index = inactiveMods.firstIndex(where: { $0.uuid == mod.uuid }) else { return }
        inactiveMods.remove(at: index)
        activeMods.append(mod)
    }

    /// Deactivate a mod (move from active to inactive).
    func deactivateMod(_ mod: ModInfo) {
        guard !mod.isBasicGameModule else { return } // Can't deactivate GustavDev
        guard let index = activeMods.firstIndex(where: { $0.uuid == mod.uuid }) else { return }
        activeMods.remove(at: index)
        inactiveMods.append(mod)
        inactiveMods.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Activate all inactive mods.
    func activateAll() {
        activeMods.append(contentsOf: inactiveMods)
        inactiveMods.removeAll()
    }

    /// Deactivate all active mods (except GustavDev).
    func deactivateAll() {
        let toDeactivate = activeMods.filter { !$0.isBasicGameModule }
        inactiveMods.append(contentsOf: toDeactivate)
        inactiveMods.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        activeMods.removeAll(where: { !$0.isBasicGameModule })
    }

    /// Move a mod in the active load order.
    func moveActiveMod(from source: IndexSet, to destination: Int) {
        activeMods.move(fromOffsets: source, toOffset: destination)
    }

    // MARK: - Save to modsettings.lsx

    /// Write the current active mod configuration to modsettings.lsx.
    func saveModSettings() async {
        do {
            // Create backup first
            if FileLocations.modSettingsExists {
                try backupService.backupModSettings()
            }

            // Unlock if locked
            backupService.unlockModSettings()

            // Write new settings
            try modSettingsService.write(activeMods: activeMods)

            // Lock to prevent game from overwriting
            let locked = backupService.lockModSettings()

            if locked {
                statusMessage = "Saved \(activeMods.count) mods to modsettings.lsx (locked)"
            } else {
                statusMessage = "Saved \(activeMods.count) mods to modsettings.lsx (WARNING: lock failed)"
            }
            await refreshBackups()
        } catch {
            showError(error)
        }
    }

    // MARK: - Profiles

    func saveProfile(name: String) async {
        do {
            let profile = try profileService.save(name: name, activeMods: activeMods)
            profiles.insert(profile, at: 0)
            statusMessage = "Profile '\(name)' saved"
        } catch {
            showError(error)
        }
    }

    func loadProfile(_ profile: ModProfile) async {
        // Reconstruct active/inactive lists from the profile
        let allMods = activeMods + inactiveMods
        var newActive: [ModInfo] = []
        var remainingUUIDs = Set(allMods.map(\.uuid))

        for uuid in profile.activeModUUIDs {
            if let mod = allMods.first(where: { $0.uuid == uuid }) {
                newActive.append(mod)
                remainingUUIDs.remove(uuid)
            } else if let entry = profile.mods.first(where: { $0.uuid == uuid }) {
                // Create a placeholder mod from the profile entry
                let mod = ModInfo(
                    uuid: entry.uuid,
                    folder: entry.folder,
                    name: entry.name,
                    author: "Unknown",
                    modDescription: "",
                    version64: entry.version64,
                    md5: entry.md5,
                    tags: [],
                    dependencies: [],
                    requiresScriptExtender: false,
                    pakFileName: nil,
                    pakFilePath: nil,
                    metadataSource: .modSettings
                )
                newActive.append(mod)
            }
        }

        let newInactive = allMods.filter { remainingUUIDs.contains($0.uuid) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        activeMods = newActive
        inactiveMods = newInactive
        statusMessage = "Loaded profile '\(profile.name)'"
    }

    func deleteProfile(_ profile: ModProfile) async {
        do {
            try profileService.delete(profile: profile)
            profiles.removeAll { $0.id == profile.id }
            statusMessage = "Deleted profile '\(profile.name)'"
        } catch {
            showError(error)
        }
    }

    // MARK: - Backups

    func restoreBackup(_ backup: BackupService.Backup) async {
        do {
            try backupService.restore(backup: backup)
            await refreshMods()
            statusMessage = "Restored from backup"
        } catch {
            showError(error)
        }
    }

    func deleteBackup(_ backup: BackupService.Backup) async {
        do {
            try backupService.delete(backup: backup)
            await refreshBackups()
        } catch {
            showError(error)
        }
    }

    // MARK: - Game Launch

    func launchGame() {
        do {
            try launchService.launchGame()
            statusMessage = "Launching Baldur's Gate 3..."
        } catch {
            showError(error)
        }
    }

    // MARK: - Import Mod

    /// Import a mod from a file URL (ZIP or .pak).
    func importMod(from url: URL) async {
        do {
            let modsFolder = FileLocations.modsFolder
            try FileLocations.ensureDirectoryExists(modsFolder)

            if url.pathExtension.lowercased() == "zip" {
                try await importZip(url)
            } else if url.pathExtension.lowercased() == "pak" {
                let destination = modsFolder.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)
            }

            await refreshMods()
            statusMessage = "Imported \(url.lastPathComponent)"
        } catch {
            showError(error)
        }
    }

    private func importZip(_ zipURL: URL) async throws {
        let modsFolder = FileLocations.modsFolder
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Use ditto to extract ZIP on macOS (handles most ZIP formats)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-xk", zipURL.path, tempDir.path]
        try process.run()
        process.waitUntilExit()

        // Find all .pak files in the extracted content
        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "pak" {
                let destination = modsFolder.appendingPathComponent(fileURL.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: fileURL, to: destination)
            }
            // Also copy info.json if found
            if fileURL.lastPathComponent.lowercased() == "info.json" {
                let destination = modsFolder.appendingPathComponent("info.json")
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: fileURL, to: destination)
            }
        }
    }

    // MARK: - Helpers

    var selectedMod: ModInfo? {
        guard let id = selectedModID else { return nil }
        return activeMods.first(where: { $0.uuid == id })
            ?? inactiveMods.first(where: { $0.uuid == id })
    }

    /// Missing dependency check for active mods.
    func missingDependencies(for mod: ModInfo) -> [ModDependency] {
        let activeUUIDs = Set(activeMods.map(\.uuid))
        return mod.dependencies.filter { dep in
            !activeUUIDs.contains(dep.uuid) &&
            dep.uuid != Constants.gustavDevUUID
        }
    }

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        statusMessage = "Error: \(error.localizedDescription)"
    }
}
