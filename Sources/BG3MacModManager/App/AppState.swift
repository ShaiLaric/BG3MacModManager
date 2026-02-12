import SwiftUI
import Combine
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
            activeMods = result.active.map { inferCategory(for: $0) }
            inactiveMods = result.inactive.map { inferCategory(for: $0) }
            statusMessage = "Found \(activeMods.count) active, \(inactiveMods.count) inactive mods"
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
        seStatus = seService.checkStatus()
    }

    // MARK: - Mod Management

    /// Activate a mod (move from inactive to active).
    func activateMod(_ mod: ModInfo) {
        guard let index = inactiveMods.firstIndex(where: { $0.uuid == mod.uuid }) else { return }
        inactiveMods.remove(at: index)
        activeMods.append(mod)
        runValidation()
    }

    /// Deactivate a mod (move from active to inactive).
    func deactivateMod(_ mod: ModInfo) {
        guard !mod.isBasicGameModule else { return }
        guard let index = activeMods.firstIndex(where: { $0.uuid == mod.uuid }) else { return }
        activeMods.remove(at: index)
        inactiveMods.append(mod)
        inactiveMods.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        runValidation()
    }

    /// Activate all inactive mods.
    func activateAll() {
        activeMods.append(contentsOf: inactiveMods)
        inactiveMods.removeAll()
        runValidation()
    }

    /// Deactivate all active mods (except GustavDev).
    func deactivateAll() {
        let toDeactivate = activeMods.filter { !$0.isBasicGameModule }
        inactiveMods.append(contentsOf: toDeactivate)
        inactiveMods.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        activeMods.removeAll(where: { !$0.isBasicGameModule })
        runValidation()
    }

    /// Move a mod in the active load order.
    func moveActiveMod(from source: IndexSet, to destination: Int) {
        activeMods.move(fromOffsets: source, toOffset: destination)
        runValidation()
    }

    // MARK: - Save to modsettings.lsx

    /// Write the current active mod configuration to modsettings.lsx.
    /// Shows a confirmation dialog if critical warnings are detected.
    func saveModSettings() async {
        let saveWarnings = validationService.validateForSave(
            activeMods: activeMods,
            inactiveMods: inactiveMods,
            seStatus: seStatus
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
            if FileLocations.modSettingsExists {
                try backupService.backupModSettings()
            }

            backupService.unlockModSettings()
            try modSettingsService.write(activeMods: activeMods)

            let locked = backupService.lockModSettings()
            statusMessage = locked
                ? "Saved \(activeMods.count) mods to modsettings.lsx (locked)"
                : "Saved \(activeMods.count) mods to modsettings.lsx (WARNING: lock failed)"

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

    /// Import a mod from a file URL (.pak, .zip, or supported archive format).
    func importMod(from url: URL) async {
        do {
            let modsFolder = FileLocations.modsFolder
            try FileLocations.ensureDirectoryExists(modsFolder)

            let ext = url.pathExtension.lowercased()

            if ext == "pak" {
                let destination = modsFolder.appendingPathComponent(url.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.copyItem(at: url, to: destination)
            } else if ArchiveService.ArchiveFormat(
                pathExtension: ext, fullFilename: url.lastPathComponent
            ) != nil {
                try await importArchive(url)
            } else {
                throw ArchiveService.ArchiveError.unsupportedFormat(ext)
            }

            await refreshMods()
            statusMessage = "Imported \(url.lastPathComponent)"
        } catch {
            showError(error)
        }
    }

    private func importArchive(_ archiveURL: URL) async throws {
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

        // For each PAK, copy it and find the nearest info.json to pair with it
        for pakURL in pakFiles {
            let pakFilename = pakURL.lastPathComponent
            let baseName = pakURL.deletingPathExtension().lastPathComponent

            // Copy PAK to Mods folder
            let pakDestination = modsFolder.appendingPathComponent(pakFilename)
            if FileManager.default.fileExists(atPath: pakDestination.path) {
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
        guard let id = selectedModID else { return nil }
        return activeMods.first(where: { $0.uuid == id })
            ?? inactiveMods.first(where: { $0.uuid == id })
    }

    /// Missing dependency check for a single mod.
    func missingDependencies(for mod: ModInfo) -> [ModDependency] {
        let activeUUIDs = Set(activeMods.map(\.uuid))
        return mod.dependencies.filter { dep in
            !activeUUIDs.contains(dep.uuid) &&
            !Constants.builtInModuleUUIDs.contains(dep.uuid)
        }
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
            seStatus: seStatus
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
            await refreshMods()
            detectDuplicateGroups()
            statusMessage = "Deleted \(mod.pakFileName ?? mod.name)"
        } catch {
            showError(error)
        }
    }

    /// Sort active mods by dependency order using topological sort.
    func autoSortByDependencies() {
        let nonBase = activeMods.filter { !$0.isBasicGameModule }
        let base = activeMods.filter { $0.isBasicGameModule }

        if let sorted = validationService.topologicalSort(mods: nonBase) {
            activeMods = base + sorted
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

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        statusMessage = "Error: \(error.localizedDescription)"
    }
}
