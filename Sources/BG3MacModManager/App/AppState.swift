import SwiftUI
import Combine
import CryptoKit
import UniformTypeIdentifiers

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

    /// Multi-selection for bulk operations (Cmd+Click, Shift+Click).
    @Published var selectedModIDs: Set<String> = []

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

    /// ZIP export progress (0.0 to 1.0).
    @Published var exportProgress: Double = 0
    @Published var isExporting: Bool = false

    /// Validation warnings for the current mod configuration.
    @Published var warnings: [ModWarning] = []

    /// Pre-save confirmation state.
    @Published var showSaveConfirmation: Bool = false
    @Published var pendingSaveWarnings: [ModWarning] = []

    /// Duplicate mod resolution state.
    @Published var showDuplicateResolver: Bool = false
    @Published var duplicateGroups: [[ModInfo]] = []

    /// External modsettings.lsx change detection — prompt user to restore from backup.
    @Published var showExternalChangeAlert: Bool = false

    /// Import progress state.
    @Published var isImporting: Bool = false

    /// Mods that were newly imported in the last import operation (for post-import activation prompt).
    @Published var lastImportedMods: [ModInfo] = []

    /// Whether to show the post-import activation prompt.
    @Published var showImportActivation: Bool = false

    /// Request to navigate to a specific sidebar tab (set by action buttons, consumed by ContentView).
    @Published var navigateToSidebarItem: String?

    /// Missing mods from the last load order import (for summary dialog).
    @Published var showImportSummary: Bool = false
    @Published var importSummaryResult: LoadOrderImportSummary?

    /// Whether the in-memory load order differs from what is saved on disk.
    @Published var hasUnsavedChanges: Bool = false

    /// Whether the initial duplicate check has been performed (auto-show only on first load).
    private var hasPerformedInitialDuplicateCheck = false

    // MARK: - Services

    let modSettingsService = ModSettingsService()
    let discoveryService = ModDiscoveryService()
    let profileService = ProfileService()
    let backupService = BackupService()
    let seService = ScriptExtenderService()
    let launchService = GameLaunchService()
    let validationService = ModValidationService()
    let textExportService = TextExportService()
    let archiveService = ArchiveService()
    let categoryService = CategoryInferenceService()
    let loadOrderImportService = LoadOrderImportService()
    let nexusURLService = NexusURLService()

    // MARK: - Initialization

    init() {
        isGameInstalled = FileLocations.isGameInstalled
    }

    func initialLoad() {
        Task {
            deleteModCrashSanityCheckIfNeeded()
            await refreshAll()
            checkForExternalModSettingsChange()
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
            activeMods = result.active.map { inferCategory(for: $0) }
            inactiveMods = result.inactive.map { inferCategory(for: $0) }
            statusMessage = "Found \(activeMods.count) active, \(inactiveMods.count) inactive mods"
            hasUnsavedChanges = false
            runValidation()
            if !hasPerformedInitialDuplicateCheck {
                hasPerformedInitialDuplicateCheck = true
                detectDuplicateGroups()
            }
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
        let status = seService.checkStatus()
        seStatus = status
        if status.isDeployed {
            seService.recordDeployed()
        }
    }

    // MARK: - Mod Management

    /// Activate a mod (move from inactive to active).
    func activateMod(_ mod: ModInfo) {
        guard let index = inactiveMods.firstIndex(where: { $0.uuid == mod.uuid }) else { return }
        inactiveMods.remove(at: index)
        activeMods.append(mod)
        hasUnsavedChanges = true
        runValidation()
    }

    /// Deactivate a mod (move from active to inactive).
    func deactivateMod(_ mod: ModInfo) {
        guard !mod.isBasicGameModule else { return }
        guard let index = activeMods.firstIndex(where: { $0.uuid == mod.uuid }) else { return }
        activeMods.remove(at: index)
        inactiveMods.append(mod)
        inactiveMods.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        hasUnsavedChanges = true
        runValidation()
    }

    /// Activate all inactive mods.
    func activateAll() {
        activeMods.append(contentsOf: inactiveMods)
        inactiveMods.removeAll()
        hasUnsavedChanges = true
        runValidation()
    }

    /// Deactivate all active mods (except GustavDev).
    func deactivateAll() {
        let toDeactivate = activeMods.filter { !$0.isBasicGameModule }
        inactiveMods.append(contentsOf: toDeactivate)
        inactiveMods.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        activeMods.removeAll(where: { !$0.isBasicGameModule })
        hasUnsavedChanges = true
        runValidation()
    }

    /// Move a mod in the active load order.
    func moveActiveMod(from source: IndexSet, to destination: Int) {
        activeMods.move(fromOffsets: source, toOffset: destination)
        hasUnsavedChanges = true
        runValidation()
    }

    /// Move an active mod to the top of the load order (after the base game module).
    func moveModToTop(_ mod: ModInfo) {
        guard !mod.isBasicGameModule,
              let index = activeMods.firstIndex(where: { $0.uuid == mod.uuid }) else { return }
        activeMods.remove(at: index)
        // Insert after the last base-game module so GustavX stays at position 0
        let insertIndex = activeMods.firstIndex(where: { !$0.isBasicGameModule }) ?? 0
        activeMods.insert(mod, at: insertIndex)
        hasUnsavedChanges = true
        runValidation()
        statusMessage = "Moved \(mod.name) to top of load order"
    }

    /// Move an active mod to the bottom of the load order.
    func moveModToBottom(_ mod: ModInfo) {
        guard !mod.isBasicGameModule,
              let index = activeMods.firstIndex(where: { $0.uuid == mod.uuid }) else { return }
        activeMods.remove(at: index)
        activeMods.append(mod)
        hasUnsavedChanges = true
        runValidation()
        statusMessage = "Moved \(mod.name) to bottom of load order"
    }

    /// Copy a formatted summary of the mod's info to the clipboard.
    func copyModInfo(_ mod: ModInfo) {
        var lines: [String] = []
        lines.append(mod.name)
        if mod.author != "Unknown" {
            lines.append("Author: \(mod.author)")
        }
        lines.append("Version: \(mod.version.description)")
        lines.append("UUID: \(mod.uuid)")
        if let category = mod.category {
            lines.append("Category: \(category.displayName)")
        }
        if !mod.folder.isEmpty {
            lines.append("Folder: \(mod.folder)")
        }
        if let nexusURL = nexusURLService.url(for: mod.uuid) {
            lines.append("Nexus: \(nexusURL)")
        }

        let text = lines.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        statusMessage = "Copied info for \(mod.name)"
    }

    /// Open the Nexus Mods page for a mod. Uses the stored URL if available,
    /// otherwise opens a Nexus search for the mod name.
    func openNexusPage(for mod: ModInfo) {
        if let urlString = nexusURLService.url(for: mod.uuid),
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        } else {
            // Fall back to a Nexus Mods search
            let query = mod.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? mod.name
            if let searchURL = URL(string: "https://www.nexusmods.com/baldursgate3/search/?gsearch=\(query)") {
                NSWorkspace.shared.open(searchURL)
            }
        }
    }

    // MARK: - Save to modsettings.lsx

    /// Write the current active mod configuration to modsettings.lsx.
    /// Shows a confirmation dialog if critical warnings are detected.
    func saveModSettings() async {
        let saveWarnings = validationService.validateForSave(
            activeMods: activeMods,
            inactiveMods: inactiveMods,
            seStatus: seStatus,
            seWasPreviouslyDeployed: seService.wasDeployed()
        )

        let hasCritical = saveWarnings.contains { $0.severity == .critical }

        if hasCritical {
            pendingSaveWarnings = saveWarnings
            showSaveConfirmation = true
            return
        }

        await performSave()
    }

    /// Actually write modsettings.lsx (called directly or after user confirms warnings).
    func performSave() async {
        do {
            deleteModCrashSanityCheckIfNeeded()

            if FileLocations.modSettingsExists {
                try backupService.backupModSettings()
            }

            backupService.unlockModSettings()
            try modSettingsService.write(activeMods: activeMods)
            recordModSettingsHash()

            let locked = backupService.lockModSettings()
            statusMessage = locked
                ? "Saved \(activeMods.count) mods to modsettings.lsx (locked)"
                : "Saved \(activeMods.count) mods to modsettings.lsx (WARNING: lock failed)"

            hasUnsavedChanges = false
            await refreshBackups()
            showSaveConfirmation = false
            pendingSaveWarnings = []
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
                    conflicts: [],
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
        hasUnsavedChanges = true
        statusMessage = "Loaded profile '\(profile.name)'"
        runValidation()
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

    /// Import a single mod from a file URL (.pak, .zip, or supported archive format).
    func importMod(from url: URL) async {
        await importMods(from: [url])
    }

    /// Import multiple mod files at once (for drag-and-drop or multi-select file picker).
    /// Tracks all new mods across the batch and prompts for activation once at the end.
    func importMods(from urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }

        let preImportUUIDs = Set((activeMods + inactiveMods).map(\.uuid))
        var totalDuplicates: [String] = []
        var importedCount = 0

        for url in urls {
            do {
                let modsFolder = FileLocations.modsFolder
                try FileLocations.ensureDirectoryExists(modsFolder)

                let ext = url.pathExtension.lowercased()

                if ext == "pak" {
                    let destination = modsFolder.appendingPathComponent(url.lastPathComponent)
                    if FileManager.default.fileExists(atPath: destination.path) {
                        totalDuplicates.append(url.lastPathComponent)
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.copyItem(at: url, to: destination)
                    importedCount += 1
                } else if ArchiveService.ArchiveFormat(
                    pathExtension: ext, fullFilename: url.lastPathComponent
                ) != nil {
                    let replaced = try await importArchive(url)
                    totalDuplicates.append(contentsOf: replaced)
                    importedCount += 1
                } else {
                    throw ArchiveService.ArchiveError.unsupportedFormat(ext)
                }
            } catch {
                showError(error)
            }
        }

        guard importedCount > 0 else { return }

        await refreshMods()

        // Identify newly appeared mods
        let allModsNow = activeMods + inactiveMods
        let newMods = allModsNow.filter { !preImportUUIDs.contains($0.uuid) }

        if !totalDuplicates.isEmpty {
            statusMessage = "Imported \(importedCount) file(s) (replaced \(totalDuplicates.count) existing)"
        } else {
            statusMessage = "Imported \(importedCount) file(s)"
        }

        if !newMods.isEmpty {
            lastImportedMods = newMods
            showImportActivation = true
        }
    }

    /// Extract an archive and copy its PAK files to the Mods folder.
    /// Returns the list of filenames that were replaced (already existed).
    private func importArchive(_ archiveURL: URL) async throws -> [String] {
        let modsFolder = FileLocations.modsFolder
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try archiveService.extract(archive: archiveURL, to: tempDir)

        // Collect all PAK and info.json files from the extracted content
        var pakFiles: [URL] = []
        var infoJsonFiles: [URL] = []

        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension.lowercased() == "pak" {
                pakFiles.append(fileURL)
            } else if fileURL.lastPathComponent.lowercased() == "info.json" {
                infoJsonFiles.append(fileURL)
            }
        }

        var duplicatesReplaced: [String] = []

        // For each PAK, copy it and find the nearest info.json to pair with it
        for pakURL in pakFiles {
            let pakFilename = pakURL.lastPathComponent
            let baseName = pakURL.deletingPathExtension().lastPathComponent

            // Copy PAK to Mods folder
            let pakDestination = modsFolder.appendingPathComponent(pakFilename)
            if FileManager.default.fileExists(atPath: pakDestination.path) {
                duplicatesReplaced.append(pakFilename)
                try FileManager.default.removeItem(at: pakDestination)
            }
            try FileManager.default.copyItem(at: pakURL, to: pakDestination)

            // Find the nearest info.json for this PAK (same dir or parent within the ZIP)
            if let infoJson = findNearestInfoJson(for: pakURL, in: infoJsonFiles, zipRoot: tempDir) {
                // Rename to <baseName>.json so discovery can match it unambiguously to this PAK
                let jsonDestination = modsFolder.appendingPathComponent("\(baseName).json")
                if FileManager.default.fileExists(atPath: jsonDestination.path) {
                    try FileManager.default.removeItem(at: jsonDestination)
                }
                try FileManager.default.copyItem(at: infoJson, to: jsonDestination)
            }
        }

        // Clean up any stale bare "info.json" in the Mods folder that could pollute discovery
        let staleInfoJson = modsFolder.appendingPathComponent("info.json")
        try? FileManager.default.removeItem(at: staleInfoJson)

        return duplicatesReplaced
    }

    /// Find the nearest info.json to a PAK file within the extracted ZIP.
    /// Checks same directory first, then parent directories up to the ZIP root.
    private func findNearestInfoJson(for pakURL: URL, in infoJsonFiles: [URL], zipRoot: URL) -> URL? {
        var searchDir = pakURL.deletingLastPathComponent()
        let rootPath = zipRoot.standardizedFileURL.path

        while searchDir.standardizedFileURL.path.hasPrefix(rootPath) {
            if let match = infoJsonFiles.first(where: {
                $0.deletingLastPathComponent().standardizedFileURL.path == searchDir.standardizedFileURL.path
            }) {
                return match
            }
            let parent = searchDir.deletingLastPathComponent()
            if parent.standardizedFileURL.path == searchDir.standardizedFileURL.path { break }
            searchDir = parent
        }
        return nil
    }

    // MARK: - Extract Mod

    /// Extract all files from a mod's .pak archive to a user-chosen folder.
    func extractMod(_ mod: ModInfo) {
        guard let pakURL = mod.pakFilePath else {
            errorMessage = "No PAK file path available for \(mod.name)"
            showError = true
            return
        }

        let panel = NSOpenPanel()
        panel.title = "Extract \(mod.name) — Choose Destination"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Extract Here"

        guard panel.runModal() == .OK, let destinationFolder = panel.url else { return }

        let folderName = mod.pakFileName?.replacingOccurrences(of: ".pak", with: "") ?? mod.folder
        let extractFolder = destinationFolder.appendingPathComponent(folderName)

        Task {
            do {
                try FileManager.default.createDirectory(at: extractFolder, withIntermediateDirectories: true)
                try PakReader.extractAll(from: pakURL, to: extractFolder)
                statusMessage = "Extracted \(mod.name) to \(extractFolder.lastPathComponent)"
                NSWorkspace.shared.open(extractFolder)
            } catch {
                self.showError(error)
            }
        }
    }

    // MARK: - Export Load Order to ZIP

    /// Export all active mod PAK files, profile JSON, and modsettings.lsx to a ZIP archive.
    func exportLoadOrderToZip() {
        guard !activeMods.isEmpty else {
            errorMessage = "No active mods to export"
            showError = true
            return
        }

        let panel = NSSavePanel()
        panel.title = "Export Load Order as ZIP"
        panel.nameFieldStringValue = "load-order-\(formattedDate()).zip"
        if let zipType = UTType(filenameExtension: "zip") {
            panel.allowedContentTypes = [zipType]
        }

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        Task {
            await performZipExport(to: destinationURL)
        }
    }

    private func performZipExport(to destinationURL: URL) async {
        isExporting = true
        exportProgress = 0
        defer {
            isExporting = false
            exportProgress = 0
        }

        do {
            var entries: [(source: URL, archivePath: String)] = []
            var missingPaks: [String] = []

            // 1. Collect PAK files from active mods (skip base game module)
            for mod in activeMods where !mod.isBasicGameModule {
                guard let pakPath = mod.pakFilePath,
                      FileManager.default.fileExists(atPath: pakPath.path) else {
                    missingPaks.append(mod.name)
                    continue
                }
                entries.append((
                    source: pakPath,
                    archivePath: "Mods/\(pakPath.lastPathComponent)"
                ))
            }

            // 2. Generate and include profile JSON snapshot
            let profileEntries = activeMods.map { ModProfileEntry(from: $0) }
            let profile = ModProfile(
                name: "Exported Load Order",
                activeModUUIDs: activeMods.map(\.uuid),
                mods: profileEntries
            )
            let profileData = try JSONEncoder.bg3PrettyPrinted.encode(profile)
            let profileTempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("profile-\(UUID().uuidString).json")
            try profileData.write(to: profileTempURL)
            defer { try? FileManager.default.removeItem(at: profileTempURL) }
            entries.append((source: profileTempURL, archivePath: "profile.json"))

            // 3. Include modsettings.lsx if it exists
            let modSettingsURL = FileLocations.modSettingsFile
            if FileManager.default.fileExists(atPath: modSettingsURL.path) {
                entries.append((
                    source: modSettingsURL,
                    archivePath: "modsettings.lsx"
                ))
            }

            // 4. Create the ZIP on a background thread
            let service = self.archiveService
            let capturedEntries = entries
            try await Task.detached {
                try service.createZip(at: destinationURL, entries: capturedEntries) { progress in
                    Task { @MainActor in
                        self.exportProgress = progress
                    }
                }
            }.value

            // 5. Report result
            let pakCount = entries.count - (FileManager.default.fileExists(atPath: modSettingsURL.path) ? 2 : 1)
            if missingPaks.isEmpty {
                statusMessage = "Exported \(pakCount) mod\(pakCount == 1 ? "" : "s") to ZIP"
            } else {
                statusMessage = "Exported to ZIP (skipped \(missingPaks.count) missing PAK file\(missingPaks.count == 1 ? "" : "s"))"
                errorMessage = "Missing PAK files: \(missingPaks.joined(separator: ", "))"
                self.showError = true
            }
        } catch {
            showError(error)
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    // MARK: - Helpers

    var selectedMod: ModInfo? {
        // Prefer selectedModID (single-click / last-clicked) if set
        if let id = selectedModID {
            if let mod = activeMods.first(where: { $0.uuid == id })
                ?? inactiveMods.first(where: { $0.uuid == id }) {
                return mod
            }
        }
        // Fall back to first item in multi-selection set
        if let firstID = selectedModIDs.first {
            return activeMods.first(where: { $0.uuid == firstID })
                ?? inactiveMods.first(where: { $0.uuid == firstID })
        }
        return nil
    }

    /// Missing dependency check for a single mod.
    func missingDependencies(for mod: ModInfo) -> [ModDependency] {
        let activeUUIDs = Set(activeMods.map(\.uuid))
        return mod.dependencies.filter { dep in
            !activeUUIDs.contains(dep.uuid) &&
            !Constants.builtInModuleUUIDs.contains(dep.uuid)
        }
    }

    /// Whether the given mod has any missing dependencies among active mods.
    func hasMissingDependencies(_ mod: ModInfo) -> Bool {
        let activeUUIDs = Set(activeMods.map(\.uuid))
        return mod.dependencies.contains { dep in
            !activeUUIDs.contains(dep.uuid) &&
            !Constants.builtInModuleUUIDs.contains(dep.uuid)
        }
    }

    /// Whether all of the given mod's dependencies are loaded before it in the active load order.
    func hasDependencyOrderIssue(_ mod: ModInfo) -> Bool {
        let positionMap = Dictionary(
            activeMods.enumerated().map { ($1.uuid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard let modPosition = positionMap[mod.uuid] else { return false }
        let activeUUIDs = Set(activeMods.map(\.uuid))
        return mod.dependencies.contains { dep in
            guard !Constants.builtInModuleUUIDs.contains(dep.uuid),
                  activeUUIDs.contains(dep.uuid),
                  let depPosition = positionMap[dep.uuid] else { return false }
            return depPosition > modPosition
        }
    }

    /// Compute the full transitive dependency tree for a mod.
    /// Returns an array of (depth, ModDependency, resolved ModInfo?) tuples in depth-first order.
    func transitiveDependencies(for mod: ModInfo) -> [(depth: Int, dependency: ModDependency, resolved: ModInfo?)] {
        let allMods = activeMods + inactiveMods
        let modsByUUID = Dictionary(allMods.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        var result: [(depth: Int, dependency: ModDependency, resolved: ModInfo?)] = []
        var visited: Set<String> = [mod.uuid]

        func walk(dependencies: [ModDependency], depth: Int) {
            for dep in dependencies {
                guard !Constants.builtInModuleUUIDs.contains(dep.uuid) else { continue }
                let resolved = modsByUUID[dep.uuid]
                result.append((depth: depth, dependency: dep, resolved: resolved))
                guard !visited.contains(dep.uuid) else { continue }
                visited.insert(dep.uuid)
                if let resolved = resolved {
                    walk(dependencies: resolved.dependencies, depth: depth + 1)
                }
            }
        }

        walk(dependencies: mod.dependencies, depth: 0)
        return result
    }

    /// Activate all missing dependencies for a specific mod.
    /// Finds mods in the inactive list that match missing dependency UUIDs and activates them.
    /// Returns the number of dependencies activated.
    @discardableResult
    func activateMissingDependencies(for mod: ModInfo) -> Int {
        let missing = missingDependencies(for: mod)
        var activated = 0
        for dep in missing {
            if let index = inactiveMods.firstIndex(where: { $0.uuid == dep.uuid }) {
                let depMod = inactiveMods.remove(at: index)
                // Insert before the dependent mod so load order is correct
                if let modIndex = activeMods.firstIndex(where: { $0.uuid == mod.uuid }) {
                    activeMods.insert(depMod, at: modIndex)
                } else {
                    activeMods.append(depMod)
                }
                activated += 1
            }
        }
        if activated > 0 {
            hasUnsavedChanges = true
            runValidation()
        }
        return activated
    }

    /// Activate all missing dependencies across all active mods.
    /// Returns the total number of dependencies activated.
    @discardableResult
    func activateAllMissingDependencies() -> Int {
        var totalActivated = 0
        // Iterate until no more can be activated (handles transitive deps)
        var changed = true
        while changed {
            changed = false
            let currentActive = activeMods // snapshot to avoid mutation during iteration
            for mod in currentActive {
                let missing = missingDependencies(for: mod)
                for dep in missing {
                    if let index = inactiveMods.firstIndex(where: { $0.uuid == dep.uuid }) {
                        let depMod = inactiveMods.remove(at: index)
                        if let modIndex = activeMods.firstIndex(where: { $0.uuid == mod.uuid }) {
                            activeMods.insert(depMod, at: modIndex)
                        } else {
                            activeMods.append(depMod)
                        }
                        totalActivated += 1
                        changed = true
                    }
                }
            }
        }
        if totalActivated > 0 {
            hasUnsavedChanges = true
            runValidation()
        }
        return totalActivated
    }

    // MARK: - Multi-Select Operations

    /// Activate all mods in the multi-selection that are currently inactive.
    func activateSelectedMods() {
        let toActivate = inactiveMods.filter { selectedModIDs.contains($0.uuid) }
        guard !toActivate.isEmpty else { return }
        for mod in toActivate {
            if let index = inactiveMods.firstIndex(where: { $0.uuid == mod.uuid }) {
                inactiveMods.remove(at: index)
                activeMods.append(mod)
            }
        }
        selectedModIDs.removeAll()
        hasUnsavedChanges = true
        runValidation()
        statusMessage = "Activated \(toActivate.count) mod(s)"
    }

    /// Deactivate all mods in the multi-selection that are currently active.
    func deactivateSelectedMods() {
        let toDeactivate = activeMods.filter {
            selectedModIDs.contains($0.uuid) && !$0.isBasicGameModule
        }
        guard !toDeactivate.isEmpty else { return }
        for mod in toDeactivate {
            if let index = activeMods.firstIndex(where: { $0.uuid == mod.uuid }) {
                activeMods.remove(at: index)
                inactiveMods.append(mod)
            }
        }
        inactiveMods.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        selectedModIDs.removeAll()
        hasUnsavedChanges = true
        runValidation()
        statusMessage = "Deactivated \(toDeactivate.count) mod(s)"
    }

    /// Move multiple selected active mods to a new position in the load order.
    func moveSelectedActiveMods(to destination: Int) {
        let selectedActive = activeMods.enumerated()
            .filter { selectedModIDs.contains($1.uuid) && !$1.isBasicGameModule }
            .map { $0 }
        guard !selectedActive.isEmpty else { return }

        let modsToMove = selectedActive.map(\.element)
        let indicesToRemove = IndexSet(selectedActive.map(\.offset))
        activeMods.move(fromOffsets: indicesToRemove, toOffset: destination)
        hasUnsavedChanges = true
        runValidation()
        statusMessage = "Moved \(modsToMove.count) mod(s)"
    }

    /// All validation warnings affecting a specific mod.
    func warnings(for mod: ModInfo) -> [ModWarning] {
        warnings.filter { $0.affectedModUUIDs.contains(mod.uuid) }
    }

    /// Run all validation checks against the current mod state.
    func runValidation() {
        warnings = validationService.validate(
            activeMods: activeMods,
            inactiveMods: inactiveMods,
            seStatus: seStatus,
            seWasPreviouslyDeployed: seService.wasDeployed()
        )
    }

    // MARK: - Duplicate Resolution

    /// Groups all mods by UUID where more than one mod shares the same UUID.
    func detectDuplicateGroups() {
        let allMods = activeMods + inactiveMods
        var uuidGroups: [String: [ModInfo]] = [:]

        for mod in allMods {
            uuidGroups[mod.uuid, default: []].append(mod)
        }

        duplicateGroups = uuidGroups.values
            .filter { $0.count > 1 }
            .sorted { ($0.first?.name ?? "") < ($1.first?.name ?? "") }

        if !duplicateGroups.isEmpty {
            showDuplicateResolver = true
        }
    }

    /// Delete a specific mod's PAK file from disk and refresh.
    func deletePakFile(for mod: ModInfo) async {
        guard let pakURL = mod.pakFilePath else { return }

        do {
            if FileManager.default.fileExists(atPath: pakURL.path) {
                try FileManager.default.removeItem(at: pakURL)
            }
            // Also remove the companion info.json if one exists
            removeCompanionInfoJson(for: pakURL)
            await refreshMods()
            detectDuplicateGroups()
            statusMessage = "Deleted \(mod.pakFileName ?? mod.name)"
        } catch {
            showError(error)
        }
    }

    // MARK: - Permanent Mod Deletion

    /// State for the delete-mod confirmation dialog.
    @Published var showDeleteModConfirmation: Bool = false
    @Published var modsToDelete: [ModInfo] = []

    /// Request permanent deletion of a single deactivated mod.
    /// Shows a confirmation dialog before proceeding.
    func requestDeleteMod(_ mod: ModInfo) {
        modsToDelete = [mod]
        showDeleteModConfirmation = true
    }

    /// Request permanent deletion of multiple selected deactivated mods.
    /// Shows a confirmation dialog before proceeding.
    func requestDeleteSelectedMods() {
        let toDelete = inactiveMods.filter {
            selectedModIDs.contains($0.uuid) && $0.pakFilePath != nil && !$0.isBasicGameModule
        }
        guard !toDelete.isEmpty else { return }
        modsToDelete = toDelete
        showDeleteModConfirmation = true
    }

    /// Permanently delete the PAK files (and companion info.json files) for the queued mods.
    /// Called after the user confirms the deletion dialog.
    func confirmDeleteMods() async {
        var deleted = 0
        for mod in modsToDelete {
            guard let pakURL = mod.pakFilePath else { continue }
            do {
                if FileManager.default.fileExists(atPath: pakURL.path) {
                    try FileManager.default.removeItem(at: pakURL)
                    removeCompanionInfoJson(for: pakURL)
                    deleted += 1
                }
            } catch {
                showError(error)
            }
        }

        let names = modsToDelete.map(\.name)
        modsToDelete = []
        showDeleteModConfirmation = false
        selectedModIDs.removeAll()

        await refreshMods()

        if deleted > 0 {
            statusMessage = "Permanently deleted \(deleted) mod\(deleted == 1 ? "" : "s"): \(names.joined(separator: ", "))"
        }
    }

    /// Remove the companion `<baseName>.json` info file that lives next to a PAK in the Mods folder.
    private func removeCompanionInfoJson(for pakURL: URL) {
        let baseName = pakURL.deletingPathExtension().lastPathComponent
        let jsonURL = pakURL.deletingLastPathComponent().appendingPathComponent("\(baseName).json")
        try? FileManager.default.removeItem(at: jsonURL)
    }

    /// Sort active mods by dependency order using topological sort.
    func autoSortByDependencies() {
        let nonBase = activeMods.filter { !$0.isBasicGameModule }
        let base = activeMods.filter { $0.isBasicGameModule }

        if let sorted = validationService.topologicalSort(mods: nonBase) {
            activeMods = base + sorted
            hasUnsavedChanges = true
            runValidation()
            statusMessage = "Mods sorted by dependency order"
        } else {
            errorMessage = "Cannot auto-sort: circular dependencies detected. Resolve cycles first."
            showError = true
        }
    }

    /// Smart sort: groups mods by category tier, then applies dependency sort within each tier.
    /// Mods without a category are placed after Tier 3 (content extensions) and before Tier 4 (visual).
    func smartSort() {
        let base = activeMods.filter { $0.isBasicGameModule }
        let nonBase = activeMods.filter { !$0.isBasicGameModule }

        // Group by tier (nil category goes into a synthetic middle tier)
        var tiers: [Int: [ModInfo]] = [:]
        for mod in nonBase {
            let tierKey = mod.category?.rawValue ?? 3 // uncategorized sorts with content extensions
            tiers[tierKey, default: []].append(mod)
        }

        var sorted: [ModInfo] = []
        // Process tiers in order: 1, 2, 3, 4, 5
        for tier in 1...5 {
            guard let modsInTier = tiers[tier], !modsInTier.isEmpty else { continue }
            // Apply topological sort within the tier for dependency correctness
            if let tierSorted = validationService.topologicalSort(mods: modsInTier) {
                sorted.append(contentsOf: tierSorted)
            } else {
                // Cycle within tier — fall back to original order
                sorted.append(contentsOf: modsInTier)
            }
        }

        activeMods = base + sorted
        hasUnsavedChanges = true
        runValidation()

        let categorized = nonBase.filter { $0.category != nil }.count
        statusMessage = "Smart sort complete (\(categorized)/\(nonBase.count) mods categorized)"
    }

    /// Set a user category override for a mod and re-infer.
    func setCategoryOverride(_ category: ModCategory?, for mod: ModInfo) {
        categoryService.setOverride(category, for: mod.uuid)
        // Re-apply inference to this mod in whichever list it's in
        if let i = activeMods.firstIndex(where: { $0.uuid == mod.uuid }) {
            activeMods[i].category = category ?? categoryService.inferCategory(for: activeMods[i])
        }
        if let i = inactiveMods.firstIndex(where: { $0.uuid == mod.uuid }) {
            inactiveMods[i].category = category ?? categoryService.inferCategory(for: inactiveMods[i])
        }
    }

    /// Infer category for a single mod using the category service.
    private func inferCategory(for mod: ModInfo) -> ModInfo {
        var m = mod
        m.category = categoryService.inferCategory(for: mod)
        return m
    }

    // MARK: - ModCrashSanityCheck Workaround

    /// Delete the ModCrashSanityCheck directory if it exists.
    /// Since Patch 8 this folder causes BG3 to deactivate externally-managed mods.
    func deleteModCrashSanityCheckIfNeeded() {
        guard FileLocations.modCrashSanityCheckExists else { return }
        do {
            try FileManager.default.removeItem(at: FileLocations.modCrashSanityCheckFolder)
            statusMessage = "Deleted ModCrashSanityCheck folder (prevents game from deactivating mods)"
        } catch {
            // Non-fatal — surface as validation warning instead
            statusMessage = "Warning: could not delete ModCrashSanityCheck folder"
        }
        runValidation()
    }

    // MARK: - Last-Exported Order Recovery

    /// Record a SHA-256 hash of the current modsettings.lsx after we write it.
    private func recordModSettingsHash() {
        guard let hash = hashOfModSettings() else { return }
        try? FileLocations.ensureDirectoryExists(FileLocations.appSupportDirectory)
        try? hash.write(to: FileLocations.lastExportHashFile, atomically: true, encoding: .utf8)
    }

    /// Compare the current modsettings.lsx against our last known export.
    /// If they differ, the game (or another tool) changed the file externally.
    private func checkForExternalModSettingsChange() {
        guard FileLocations.modSettingsExists else { return }
        guard let storedHash = try? String(contentsOf: FileLocations.lastExportHashFile, encoding: .utf8) else { return }
        guard let currentHash = hashOfModSettings() else { return }

        if storedHash != currentHash {
            showExternalChangeAlert = true
        }
    }

    /// Restore modsettings.lsx from the most recent backup (used when external change detected).
    func restoreFromLatestBackup() async {
        do {
            let allBackups = try backupService.listBackups()
            guard let latest = allBackups.first else {
                errorMessage = "No backups available to restore from."
                showError = true
                return
            }
            try backupService.restore(backup: latest)
            await refreshMods()
            recordModSettingsHash()
            statusMessage = "Restored modsettings.lsx from backup (\(latest.displayName))"
        } catch {
            showError(error)
        }
    }

    /// SHA-256 of the current modsettings.lsx file on disk.
    private func hashOfModSettings() -> String? {
        guard let data = try? Data(contentsOf: FileLocations.modSettingsFile) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Import from Save File

    /// Import mod load order from a BG3 save file (.lsv).
    /// Save files are LSPK archives containing modsettings.lsx.
    func importFromSaveFile(url: URL) async {
        do {
            // 1. List files in the archive and find modsettings.lsx
            let entries = try PakReader.listFiles(at: url)
            guard let settingsEntry = entries.first(where: {
                $0.name.hasSuffix("modsettings.lsx") ||
                $0.name.replacingOccurrences(of: "\\", with: "/").hasSuffix("modsettings.lsx")
            }) else {
                errorMessage = "No modsettings.lsx found in save file."
                showError = true
                return
            }

            // 2. Extract and parse
            let data = try PakReader.extractFile(named: settingsEntry.name, from: url)
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("save-modsettings-\(UUID().uuidString).lsx")
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }

            let settings = try modSettingsService.read(from: tempURL)

            // 3. Reconstruct active/inactive lists from save data
            let allMods = activeMods + inactiveMods
            var newActive: [ModInfo] = []
            var usedUUIDs: Set<String> = []

            for uuid in settings.modOrder {
                guard !Constants.builtInModuleUUIDs.contains(uuid) else { continue }

                if let mod = allMods.first(where: { $0.uuid == uuid }) {
                    newActive.append(mod)
                    usedUUIDs.insert(uuid)
                } else if let desc = settings.mods[uuid] {
                    // Create placeholder for mods we don't have on disk
                    let mod = ModInfo(
                        uuid: desc.uuid,
                        folder: desc.folder,
                        name: desc.name,
                        author: "Unknown",
                        modDescription: "",
                        version64: Int64(desc.version64) ?? 36028797018963968,
                        md5: desc.md5,
                        tags: [],
                        dependencies: [],
                        conflicts: [],
                        requiresScriptExtender: false,
                        pakFileName: nil,
                        pakFilePath: nil,
                        metadataSource: .modSettings
                    )
                    newActive.append(mod)
                    usedUUIDs.insert(uuid)
                }
            }

            let newInactive = allMods
                .filter { !usedUUIDs.contains($0.uuid) && !$0.isBasicGameModule }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            // Keep base game module at the front
            let base = allMods.filter { $0.isBasicGameModule }
            activeMods = base + newActive.map { inferCategory(for: $0) }
            inactiveMods = newInactive.map { inferCategory(for: $0) }

            hasUnsavedChanges = true
            runValidation()
            statusMessage = "Imported load order from save file (\(newActive.count) mods)"
        } catch {
            showError(error)
        }
    }

    // MARK: - Import Load Order (BG3MM / LSX)

    /// Import a load order from an external file (BG3MM JSON or standalone modsettings.lsx).
    func importLoadOrder(from url: URL) async {
        do {
            let result = try loadOrderImportService.parseFile(at: url)

            guard !result.entries.isEmpty else {
                errorMessage = "The imported file contains no mods."
                showError = true
                return
            }

            let allMods = activeMods + inactiveMods
            var newActive: [ModInfo] = []
            var usedUUIDs: Set<String> = []
            var missingMods: [MissingModInfo] = []

            for entry in result.entries {
                guard !Constants.builtInModuleUUIDs.contains(entry.uuid) else { continue }

                if let mod = allMods.first(where: { $0.uuid == entry.uuid }) {
                    newActive.append(mod)
                    usedUUIDs.insert(entry.uuid)
                } else {
                    missingMods.append(MissingModInfo(
                        id: entry.uuid,
                        name: entry.name,
                        uuid: entry.uuid,
                        nexusURL: nexusURLService.url(for: entry.uuid)
                    ))
                }
            }

            let newInactive = allMods
                .filter { !usedUUIDs.contains($0.uuid) && !$0.isBasicGameModule }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

            let base = allMods.filter { $0.isBasicGameModule }
            activeMods = base + newActive.map { inferCategory(for: $0) }
            inactiveMods = newInactive.map { inferCategory(for: $0) }

            hasUnsavedChanges = true
            runValidation()

            let totalInFile = result.entries.filter {
                !Constants.builtInModuleUUIDs.contains($0.uuid)
            }.count

            if missingMods.isEmpty {
                statusMessage = "Imported load order from \(result.sourceName) (\(newActive.count) mods)"
            } else {
                importSummaryResult = LoadOrderImportSummary(
                    format: result.sourceName,
                    totalInFile: totalInFile,
                    matchedCount: newActive.count,
                    missingMods: missingMods
                )
                showImportSummary = true
                statusMessage = "Imported load order (\(newActive.count) matched, \(missingMods.count) missing)"
            }
        } catch {
            showError(error)
        }
    }

    // MARK: - Nexus URL

    /// Set the Nexus Mods URL for a mod.
    func setNexusURL(_ url: String?, for mod: ModInfo) {
        nexusURLService.setURL(url, for: mod.uuid)
        objectWillChange.send()
    }

    // MARK: - Error Handling

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        statusMessage = "Error: \(error.localizedDescription)"
    }
}

// MARK: - Import Summary Types

struct LoadOrderImportSummary {
    let format: String
    let totalInFile: Int
    let matchedCount: Int
    let missingMods: [MissingModInfo]
}

struct MissingModInfo: Identifiable {
    let id: String
    let name: String
    let uuid: String
    let nexusURL: String?
}
