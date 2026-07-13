// SPDX-License-Identifier: GPL-3.0-or-later

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

    /// Whether to show the custom mod import file picker.
    @Published var showModImportPicker: Bool = false

    /// Request to navigate to a specific sidebar tab (set by action buttons, consumed by ContentView).
    @Published var navigateToSidebarItem: String?

    /// Missing mods from the last load order import (for summary dialog).
    @Published var showImportSummary: Bool = false
    @Published var importSummaryResult: LoadOrderImportSummary?

    /// Whether the in-memory load order differs from what is saved on disk.
    @Published var hasUnsavedChanges: Bool = false

    /// Nexus Mods update check results.
    @Published var nexusUpdateResults: [String: NexusUpdateResult] = [:]
    @Published var nexusUpdatePreferences: [String: NexusUpdatePreference] = [:]
    @Published var isCheckingForUpdates: Bool = false
    @Published var updateCheckProgress: (checked: Int, total: Int) = (0, 0)

    /// Persistent global constraints used by sorting and validation.
    @Published var loadOrderRules: [LoadOrderRule] = []
    @Published var showLoadOrderRules: Bool = false

    /// Latest immutable preflight report.
    @Published var readinessReport: LaunchReadinessReport?
    @Published var isCheckingReadiness: Bool = false
    @Published var showLaunchReadinessBeforeLaunch: Bool = false

    /// Discovered saves and explicit campaign/save profile associations.
    @Published var saveGames: [SaveGameSummary] = []
    @Published var saveProfileAssociations: [SaveProfileAssociation] = []
    @Published var selectedSaveID: String?
    @Published var isScanningSaveGames: Bool = false

    /// Transactional manual-update workflow and durable rollback history.
    @Published var modUpdateHistory: [ModUpdateHistoryRecord] = []
    @Published var modUpdateProvenance: [String: ModUpdateProvenance] = [:]
    @Published var modUpdateTarget: ModInfo?
    @Published var pendingModUpdatePlan: ModUpdatePlan?
    @Published var showModUpdatePicker: Bool = false
    @Published var isUpdatingMod: Bool = false
    @Published var modUpdateProgress = ModUpdateProgress(stage: .idle, completed: 0, total: 0)

    /// Whether the initial duplicate check has been performed (auto-show only on first load).
    private var hasPerformedInitialDuplicateCheck = false

    // MARK: - Undo/Redo

    /// Snapshot of a load order state for undo/redo.
    struct LoadOrderSnapshot {
        let activeMods: [ModInfo]
        let inactiveMods: [ModInfo]
    }

    /// Stack of previous states for undo.
    private var undoStack: [LoadOrderSnapshot] = []

    /// Stack of undone states for redo.
    private var redoStack: [LoadOrderSnapshot] = []

    /// Maximum number of undo levels to retain.
    private let maxUndoLevels = 50

    /// Whether an undo operation is available.
    var canUndo: Bool { !undoStack.isEmpty }

    /// Whether a redo operation is available.
    var canRedo: Bool { !redoStack.isEmpty }

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
    let modNotesService = ModNotesService()
    let nexusAPIService = NexusAPIService()
    let nexusUpdatePreferenceService = NexusUpdatePreferenceService()
    let loadOrderRuleService = LoadOrderRuleService()
    let loadOrderSolver = LoadOrderSolver()
    let launchReadinessService = LaunchReadinessService()
    let saveGameScanner = SaveGameScanner()
    let saveProfileAssociationService = SaveProfileAssociationService()
    let saveProfileComparator = SaveProfileComparator()
    let modUpdateHistoryService = ModUpdateHistoryService()
    let modUpdateService = ModUpdateService()

    // MARK: - Initialization

    init() {
        isGameInstalled = FileLocations.isGameInstalled
    }

    func initialLoad() {
        Task {
            loadPersistedLoadOrderRules()
            loadPersistedSaveProfileAssociations()
            loadPersistedModUpdateHistory()
            loadPersistedNexusUpdatePreferences()
            deleteModCrashSanityCheckIfNeeded()
            await refreshAll()
            checkForExternalModSettingsChange()

            // Auto-check for Nexus updates if enabled
            if UserDefaults.standard.bool(forKey: AppPreferenceKey.autoCheckNexusUpdates),
               nexusAPIService.apiKey != nil {
                await checkForNexusUpdates()
            }
        }
    }

    // MARK: - Refresh

    func refreshAll() async {
        isLoading = true
        defer { isLoading = false }

        // Script Extender state is an input to mod validation. Refresh it before
        // discovering mods so the initial validation cannot use a nil/stale status.
        refreshSEStatus()
        await refreshMods()
        await refreshProfiles()
        await refreshBackups()
        await refreshSaveGames()
    }

    func refreshMods() async {
        do {
            let service = discoveryService
            let result = try await Task.detached(priority: .userInitiated) {
                try service.discoverModsWithState()
            }.value
            if hasUnsavedChanges {
                let merged = ImportDiscoveryMerger.merge(
                    previousActive: activeMods,
                    previousInactive: inactiveMods,
                    hadUnsavedChanges: true,
                    discovered: result.active + result.inactive
                )
                activeMods = merged.active.map { inferCategory(for: $0) }
                inactiveMods = merged.inactive.map { inferCategory(for: $0) }
            } else {
                activeMods = result.active.map { inferCategory(for: $0) }
                inactiveMods = result.inactive.map { inferCategory(for: $0) }
                hasUnsavedChanges = false
            }
            duplicateGroups = result.duplicateGroups
            statusMessage = "Found \(activeMods.count) active, \(inactiveMods.count) inactive mods"
            runValidation()
            if !hasPerformedInitialDuplicateCheck {
                hasPerformedInitialDuplicateCheck = true
                showDuplicateResolver = !duplicateGroups.isEmpty
            }
        } catch {
            showError(error)
        }
    }

    func refreshProfiles() async {
        do {
            profiles = try await Task.detached {
                try ProfileService().listProfiles()
            }.value
        } catch {
            showError(error)
        }
    }

    func refreshBackups() async {
        do {
            backups = try await Task.detached {
                try BackupService().listBackups()
            }.value
        } catch {
            showError(error)
        }
    }

    func refreshSaveGames() async {
        isScanningSaveGames = true
        defer { isScanningSaveGames = false }
        do {
            saveGames = try await saveGameScanner.scan()
            if selectedSaveID == nil || !saveGames.contains(where: { $0.id == selectedSaveID }) {
                selectedSaveID = saveGames.first?.id
            }
            readinessReport = nil
        } catch is CancellationError {
            statusMessage = "Save scan cancelled"
        } catch {
            showError(error)
        }
    }

    func refreshSEStatus() {
        let status = seService.checkStatus()
        if status.isDeployed {
            seService.recordDeployed()
        }
        applySEStatus(status)
    }

    /// Publish a newly detected SE status and keep warnings synchronized with it.
    /// Kept separate from filesystem detection so the state transition is testable.
    func applySEStatus(_ status: ScriptExtenderService.SEStatus) {
        seStatus = status
        runValidation()
    }

    // MARK: - Undo/Redo Operations

    /// Save the current load order state to the undo stack before making changes.
    private func saveSnapshot() {
        let snapshot = LoadOrderSnapshot(activeMods: activeMods, inactiveMods: inactiveMods)
        undoStack.append(snapshot)
        if undoStack.count > maxUndoLevels {
            undoStack.removeFirst()
        }
        redoStack.removeAll()
    }

    /// Undo the last load order change.
    func undo() {
        guard let snapshot = undoStack.popLast() else { return }
        let current = LoadOrderSnapshot(activeMods: activeMods, inactiveMods: inactiveMods)
        redoStack.append(current)
        activeMods = snapshot.activeMods
        inactiveMods = snapshot.inactiveMods
        hasUnsavedChanges = true
        runValidation()
        statusMessage = "Undid last change"
    }

    /// Redo the last undone load order change.
    func redo() {
        guard let snapshot = redoStack.popLast() else { return }
        let current = LoadOrderSnapshot(activeMods: activeMods, inactiveMods: inactiveMods)
        undoStack.append(current)
        activeMods = snapshot.activeMods
        inactiveMods = snapshot.inactiveMods
        hasUnsavedChanges = true
        runValidation()
        statusMessage = "Redid last change"
    }

    // MARK: - Mod Management

    /// Activate a mod, optionally at a one-based load-order position.
    /// A nil position preserves the traditional append-to-end behavior.
    func activateMod(_ mod: ModInfo, atLoadOrderPosition position: Int? = nil) {
        let insertionIndex: Int
        if let position {
            insertionIndex = min(max(position - 1, 0), activeMods.count)
        } else {
            insertionIndex = activeMods.count
        }

        if position != nil, !canActivate(mod, at: insertionIndex) { return }
        guard activateInactiveMod(mod, at: insertionIndex) else { return }
        if position != nil {
            statusMessage = "Activated \(mod.name) at load order position \(insertionIndex + 1)"
        }
    }

    /// Activate a mod at a zero-based insertion index used by drag and drop.
    func activateModAtPosition(_ mod: ModInfo, at index: Int) {
        let insertionIndex = min(max(index, 0), activeMods.count)
        guard canActivate(mod, at: insertionIndex) else { return }
        _ = activateInactiveMod(mod, at: insertionIndex)
    }

    @discardableResult
    private func activateInactiveMod(_ mod: ModInfo, at insertionIndex: Int) -> Bool {
        guard let inactiveIndex = inactiveMods.firstIndex(where: { $0.uuid == mod.uuid }) else {
            return false
        }
        saveSnapshot()
        let activatedMod = inactiveMods.remove(at: inactiveIndex)
        activeMods.insert(activatedMod, at: insertionIndex)
        hasUnsavedChanges = true
        runValidation()
        return true
    }

    private func canActivate(_ mod: ModInfo, at insertionIndex: Int) -> Bool {
        let currentViolations = Set(
            LoadOrderSolver.violations(mods: activeMods, rules: loadOrderRules).map(\.ruleID)
        )
        var proposed = activeMods
        proposed.insert(mod, at: min(max(insertionIndex, 0), proposed.count))
        let newViolation = LoadOrderSolver.violations(mods: proposed, rules: loadOrderRules)
            .first { violation in
                !currentViolations.contains(violation.ruleID) ||
                    violation.affectedModUUIDs.contains(ModIdentity.comparisonKey(mod.uuid))
            }
        guard let newViolation else { return true }

        errorMessage = "Cannot activate at that position because it violates a load-order rule. \(newViolation.message)"
        showError = true
        return false
    }

    /// Deactivate a mod (move from active to inactive).
    func deactivateMod(_ mod: ModInfo) {
        guard !mod.isBasicGameModule else { return }
        guard let index = activeMods.firstIndex(where: { $0.uuid == mod.uuid }) else { return }
        saveSnapshot()
        activeMods.remove(at: index)
        inactiveMods.append(mod)
        inactiveMods.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        hasUnsavedChanges = true
        runValidation()
    }

    /// Activate all inactive mods.
    func activateAll() {
        saveSnapshot()
        activeMods.append(contentsOf: inactiveMods)
        inactiveMods.removeAll()
        hasUnsavedChanges = true
        runValidation()
    }

    /// Deactivate all active mods (except GustavDev).
    func deactivateAll() {
        saveSnapshot()
        let toDeactivate = activeMods.filter { !$0.isBasicGameModule }
        inactiveMods.append(contentsOf: toDeactivate)
        inactiveMods.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        activeMods.removeAll(where: { !$0.isBasicGameModule })
        hasUnsavedChanges = true
        runValidation()
    }

    /// Move a mod in the active load order.
    func moveActiveMod(from source: IndexSet, to destination: Int) {
        saveSnapshot()
        activeMods.move(fromOffsets: source, toOffset: destination)
        hasUnsavedChanges = true
        runValidation()
    }

    /// Move an active mod to the top of the load order (after the base game module).
    func moveModToTop(_ mod: ModInfo) {
        guard !mod.isBasicGameModule,
              let index = activeMods.firstIndex(where: { $0.uuid == mod.uuid }) else { return }
        saveSnapshot()
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
        saveSnapshot()
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
        if let note = modNotesService.note(for: mod.uuid) {
            lines.append("Note: \(note)")
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
            seWasPreviouslyDeployed: seService.wasDeployed(),
            loadOrderRules: loadOrderRules
        )

        let hasCritical = saveWarnings.contains { $0.severity == .critical }

        if hasCritical {
            pendingSaveWarnings = saveWarnings
            showSaveConfirmation = true
            return
        }

        _ = await performSave()
    }

    /// Actually write modsettings.lsx (called directly or after user confirms warnings).
    /// Returns true only when the new load order was written successfully.
    @discardableResult
    func performSave() async -> Bool {
        let preferences = SavePreferences()
        let settingsExisted = FileLocations.modSettingsExists
        let wasLocked = settingsExisted && backupService.isModSettingsLocked()

        do {
            deleteModCrashSanityCheckIfNeeded()

            if settingsExisted && preferences.autoBackup {
                try backupService.backupModSettings()
            }

            if settingsExisted && !backupService.unlockModSettings() && wasLocked {
                throw SaveError.unlockFailed
            }
            try modSettingsService.write(activeMods: activeMods)
            recordModSettingsHash()

            if preferences.lockAfterSave {
                let locked = backupService.lockModSettings()
                statusMessage = locked
                    ? "Saved \(activeMods.count) mods to modsettings.lsx (locked)"
                    : "Saved \(activeMods.count) mods to modsettings.lsx (WARNING: lock failed)"
            } else {
                statusMessage = "Saved \(activeMods.count) mods to modsettings.lsx"
            }

            hasUnsavedChanges = false
            readinessReport = nil

            if preferences.autoBackup && preferences.backupRetentionDays > 0 {
                do {
                    try backupService.pruneBackups(
                        olderThanDays: preferences.backupRetentionDays
                    )
                } catch {
                    statusMessage += " (old-backup cleanup failed)"
                }
            }

            await refreshBackups()
            showSaveConfirmation = false
            pendingSaveWarnings = []
            return true
        } catch {
            // A failed write must not silently change the file's prior lock state.
            if wasLocked {
                _ = backupService.lockModSettings()
            }
            showError(error)
            return false
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
        saveSnapshot()
        // Reconstruct active/inactive lists from the profile
        let allMods = activeMods + inactiveMods
        let requiredGameModules = allMods.filter(\.isBasicGameModule)
        var newActive = requiredGameModules
        var remainingUUIDs = Set(allMods.map { ModIdentity.comparisonKey($0.uuid) })
        for module in requiredGameModules {
            remainingUUIDs.remove(ModIdentity.comparisonKey(module.uuid))
        }
        var missingMods: [MissingModInfo] = []
        var matchedCount = 0

        for uuid in profile.activeModUUIDs {
            let uuidKey = ModIdentity.comparisonKey(uuid)
            guard !Constants.requiredGameModuleUUIDs.contains(uuidKey) else { continue }
            if let mod = allMods.first(where: {
                ModIdentity.comparisonKey($0.uuid) == uuidKey
            }) {
                newActive.append(mod)
                remainingUUIDs.remove(uuidKey)
                matchedCount += 1
            } else if let entry = profile.mods.first(where: {
                ModIdentity.comparisonKey($0.uuid) == uuidKey
            }) {
                // Create a placeholder mod from the profile entry
                let mod = ModInfo(
                    uuid: uuidKey,
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
                missingMods.append(MissingModInfo(
                    id: uuidKey,
                    name: entry.name,
                    uuid: uuidKey,
                    nexusURL: nexusURLService.url(for: uuidKey)
                ))
            }
        }

        let newInactive = allMods.filter {
            remainingUUIDs.contains(ModIdentity.comparisonKey($0.uuid))
        }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let base = newActive.filter(\.isBasicGameModule)
        let userMods = newActive.filter { !$0.isBasicGameModule }
        switch loadOrderSolver.solve(
            mods: userMods,
            rules: loadOrderRules,
            mode: .dependenciesOnly
        ) {
        case .ordered(let ordered):
            activeMods = base + ordered
        case .conflict(let conflict):
            activeMods = newActive
            errorMessage = "Loaded the profile, but its load order could not satisfy persistent rules: \(conflict.message)"
            showError = true
        }
        inactiveMods = newInactive
        hasUnsavedChanges = true
        runValidation()

        if missingMods.isEmpty {
            statusMessage = "Loaded profile '\(profile.name)'"
        } else {
            importSummaryResult = LoadOrderImportSummary(
                format: "Profile: \(profile.name)",
                totalInFile: profile.activeModUUIDs.count,
                matchedCount: matchedCount,
                missingMods: missingMods
            )
            showImportSummary = true
            statusMessage = "Loaded profile '\(profile.name)' (\(matchedCount) matched, \(missingMods.count) missing)"
        }

        if UserDefaults.standard.bool(forKey: AppPreferenceKey.autoSaveOnProfileLoad) {
            _ = await performSave()
        }
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

    func renameProfile(_ profile: ModProfile, to newName: String) async {
        do {
            let updated = try profileService.rename(profile: profile, to: newName)
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = updated
            }
            statusMessage = "Renamed profile to '\(newName)'"
        } catch {
            showError(error)
        }
    }

    func updateProfile(_ profile: ModProfile) async {
        do {
            let updated = try profileService.update(profile: profile, activeMods: activeMods)
            if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                profiles[index] = updated
            }
            statusMessage = "Updated profile '\(profile.name)' with current load order"
        } catch {
            showError(error)
        }
    }

    // MARK: - Save/Profile Associations

    var selectedSave: SaveGameSummary? {
        guard let selectedSaveID else { return nil }
        return saveGames.first { $0.id == selectedSaveID }
    }

    func resolvedAssociation(for save: SaveGameSummary) -> ResolvedSaveProfileAssociation? {
        saveProfileAssociationService.resolvedAssociation(
            for: save,
            in: saveProfileAssociations
        )
    }

    func associatedProfile(for save: SaveGameSummary) -> ModProfile? {
        guard let resolved = resolvedAssociation(for: save) else { return nil }
        return profiles.first { $0.id == resolved.association.profileID }
    }

    func saveProfileComparison(for save: SaveGameSummary) -> SaveProfileComparison? {
        guard let profile = associatedProfile(for: save) else { return nil }
        return saveProfileComparator.compare(
            save: save,
            profile: profile,
            activeMods: activeMods,
            installedMods: activeMods + inactiveMods
        )
    }

    func associations(for profile: ModProfile) -> [SaveProfileAssociation] {
        saveProfileAssociations.filter { $0.profileID == profile.id }
    }

    func associate(
        _ save: SaveGameSummary,
        kind: SaveProfileAssociation.TargetKind,
        with profile: ModProfile
    ) {
        let previous = saveProfileAssociations
        saveProfileAssociations = saveProfileAssociationService.upserting(
            kind: kind,
            save: save,
            profileID: profile.id,
            in: previous
        )
        do {
            try saveProfileAssociationService.saveAssociations(saveProfileAssociations)
            readinessReport = nil
            let target = kind == .campaign ? save.campaignName : save.displayName
            statusMessage = "Associated \(target) with profile '\(profile.name)'"
        } catch {
            saveProfileAssociations = previous
            showError(error)
        }
    }

    func removeAssociation(_ association: SaveProfileAssociation) {
        let previous = saveProfileAssociations
        saveProfileAssociations.removeAll { $0.id == association.id }
        do {
            try saveProfileAssociationService.saveAssociations(saveProfileAssociations)
            readinessReport = nil
            statusMessage = "Removed save/profile association"
        } catch {
            saveProfileAssociations = previous
            showError(error)
        }
    }

    func prepareToPlay(_ save: SaveGameSummary) async {
        selectedSaveID = save.id
        guard let resolved = resolvedAssociation(for: save) else {
            errorMessage = "Associate this save or campaign with a profile before preparing it."
            showError = true
            return
        }
        guard let profile = profiles.first(where: { $0.id == resolved.association.profileID }) else {
            errorMessage = "The associated profile no longer exists. Choose another profile for this save."
            showError = true
            return
        }

        await loadProfile(profile)
        _ = await refreshLaunchReadiness()
        navigateToSidebarItem = "readiness"
        statusMessage = "Prepared '\(profile.name)' for \(save.displayName); review readiness before launching"
    }

    private func loadPersistedSaveProfileAssociations() {
        do {
            saveProfileAssociations = try saveProfileAssociationService.loadAssociations()
        } catch {
            showError(error)
        }
    }

    private func saveAssociationReadinessFindings() -> [ReadinessFinding] {
        guard let save = selectedSave else { return [] }
        if let readError = save.readError {
            return [ReadinessFinding(
                id: "save-unreadable:\(save.id):\(readError)",
                severity: .warning,
                category: .saves,
                title: "Selected save could not be inspected",
                detail: readError,
                affectedModUUIDs: [],
                affectedPaths: [save.fileURL],
                action: .viewSaves
            )]
        }
        guard let resolved = resolvedAssociation(for: save) else { return [] }
        guard let profile = profiles.first(where: { $0.id == resolved.association.profileID }) else {
            return [ReadinessFinding(
                id: "save-profile-missing:\(resolved.association.id.uuidString)",
                severity: .warning,
                category: .saves,
                title: "Associated profile no longer exists",
                detail: "\(resolved.association.targetDisplayName) references a deleted profile. Choose a replacement association.",
                affectedModUUIDs: [],
                affectedPaths: [save.fileURL],
                action: .viewSaves
            )]
        }

        let comparison = saveProfileComparator.compare(
            save: save,
            profile: profile,
            activeMods: activeMods,
            installedMods: activeMods + inactiveMods
        )
        var findings: [ReadinessFinding] = []
        if comparison.hasCurrentMismatch {
            findings.append(ReadinessFinding(
                id: "save-profile-current:\(save.id):\(profile.id.uuidString):\(comparison.summary)",
                severity: comparison.missingInstalledUUIDs.isEmpty ? .warning : .critical,
                category: .saves,
                title: "Current setup does not match '\(profile.name)'",
                detail: comparison.summary,
                affectedModUUIDs: comparison.missingInstalledUUIDs + comparison.extraActiveUUIDs,
                affectedPaths: [save.fileURL],
                action: .loadProfile(profile.id)
            ))
        } else if comparison.saveOrderDiffersFromProfile {
            findings.append(ReadinessFinding(
                id: "save-profile-recorded:\(save.id):\(profile.id.uuidString)",
                severity: .information,
                category: .saves,
                title: "Save recorded a different mod order",
                detail: "The selected save's recorded order differs from its associated profile '\(profile.name)'.",
                affectedModUUIDs: save.mods.map(\.uuid),
                affectedPaths: [save.fileURL],
                action: .viewSaves
            ))
        }
        return findings
    }

    // MARK: - Backups

    func restoreBackup(_ backup: BackupService.Backup) async {
        do {
            try backupService.restore(backup: backup)
            hasUnsavedChanges = false
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

    func launchGame() async {
        let report = await refreshLaunchReadiness()
        if !report.criticalFindings.isEmpty {
            showLaunchReadinessBeforeLaunch = true
            return
        }
        await performLaunchAfterReadiness()
    }

    func launchDespiteReadiness() async {
        showLaunchReadinessBeforeLaunch = false
        await performLaunchAfterReadiness()
    }

    private func performLaunchAfterReadiness() async {
        if UserDefaults.standard.bool(forKey: AppPreferenceKey.autoSaveBeforeLaunch),
           hasUnsavedChanges,
           !(await performSave()) {
            statusMessage = "Launch cancelled because the load order could not be saved"
            return
        }
        do {
            try launchService.launchGame()
            statusMessage = "Launching Baldur's Gate 3..."
        } catch {
            showError(error)
        }
    }

    @discardableResult
    func refreshLaunchReadiness() async -> LaunchReadinessReport {
        isCheckingReadiness = true
        defer { isCheckingReadiness = false }

        runValidation()
        let snapshot = LaunchReadinessSnapshot(
            activeMods: activeMods,
            inactiveMods: inactiveMods,
            validationWarnings: warnings,
            hasUnsavedChanges: hasUnsavedChanges,
            externalModSettingsChangeDetected: showExternalChangeAlert,
            modSettingsExists: FileLocations.modSettingsExists,
            gameInstalled: FileLocations.isGameInstalled,
            steamRunning: launchService.isSteamRunning(),
            gameRunning: launchService.isGameRunning(),
            nexusConfigured: nexusAPIService.apiKey != nil,
            nexusCheckInProgress: isCheckingForUpdates,
            nexusResults: Array(nexusUpdateResults.values),
            suppressedNexusResultIDs: Set(
                nexusUpdateResults.values
                    .filter(isNexusResultSuppressed)
                    .map { ModIdentity.comparisonKey($0.modUUID) }
            ),
            additionalFindings: saveAssociationReadinessFindings()
        )
        let report = await launchReadinessService.evaluate(snapshot)
        readinessReport = report
        return report
    }

    func performReadinessAction(_ action: ReadinessAction) async {
        var shouldRecheck = true
        switch action {
        case .refresh:
            await refreshAll()
        case .saveLoadOrder:
            await saveModSettings()
        case .smartSort:
            smartSort()
        case .deactivateMod(let uuid):
            if let mod = activeMods.first(where: {
                ModIdentity.comparisonKey($0.uuid) == ModIdentity.comparisonKey(uuid)
            }) {
                deactivateMod(mod)
            }
        case .activateDependencies(let uuid):
            if let mod = activeMods.first(where: {
                ModIdentity.comparisonKey($0.uuid) == ModIdentity.comparisonKey(uuid)
            }) {
                _ = activateMissingDependencies(for: mod)
            }
        case .deleteModCrashSanityCheck:
            deleteModCrashSanityCheckIfNeeded()
        case .restoreModSettings:
            await restoreFromLatestBackup()
        case .viewScriptExtender:
            navigateToSidebarItem = "scriptExtender"
            shouldRecheck = false
        case .openModsFolder:
            launchService.openModsFolder()
            shouldRecheck = false
        case .manageRules:
            showLoadOrderRules = true
            shouldRecheck = false
        case .viewUpdates:
            navigateToSidebarItem = "updates"
            shouldRecheck = false
        case .viewSaves:
            navigateToSidebarItem = "saves"
            shouldRecheck = false
        case .loadProfile(let profileID):
            if let profile = profiles.first(where: { $0.id == profileID }) {
                await loadProfile(profile)
            }
        }

        if shouldRecheck {
            _ = await refreshLaunchReadiness()
        }
    }

    // MARK: - Transactional Mod Updates

    func beginModUpdate(for mod: ModInfo) {
        guard !mod.isBasicGameModule, mod.pakFilePath != nil else {
            errorMessage = "Only installed user mods can be updated."
            showError = true
            return
        }
        modUpdateTarget = mod
        showModUpdatePicker = true
    }

    func inspectModUpdate(sourceURL: URL) async {
        guard let target = modUpdateTarget else { return }
        isUpdatingMod = true
        modUpdateProgress = .init(stage: .inspecting, completed: 0, total: 1)
        defer { isUpdatingMod = false }

        let activeUserMods = activeMods.filter { !$0.isBasicGameModule }
        let position = activeUserMods.firstIndex(where: {
            ModIdentity.comparisonKey($0.uuid) == ModIdentity.comparisonKey(target.uuid)
        }).map { $0 + 1 }
        do {
            let plan = try await modUpdateService.inspect(
                sourceURL: sourceURL,
                target: target,
                wasActive: position != nil,
                previousUserPosition: position,
                nexusURL: nexusURLService.url(for: target.uuid)
            )
            pendingModUpdatePlan = plan
            modUpdateProgress = .init(stage: .idle, completed: 1, total: 1)
        } catch {
            modUpdateTarget = nil
            showError(error)
        }
    }

    func applyPendingModUpdate() async {
        guard let plan = pendingModUpdatePlan else { return }
        isUpdatingMod = true
        defer { isUpdatingMod = false }
        do {
            let record = try await modUpdateService.execute(plan) { progress in
                await MainActor.run { self.modUpdateProgress = progress }
            }
            pendingModUpdatePlan = nil
            modUpdateTarget = nil
            loadPersistedModUpdateHistory()
            readinessReport = nil
            await refreshMods()
            statusMessage = "Updated \(record.modName) transactionally; the previous version is available in Update History"
        } catch {
            pendingModUpdatePlan = nil
            modUpdateTarget = nil
            loadPersistedModUpdateHistory()
            await refreshMods()
            showError(error)
        }
    }

    func cancelPendingModUpdate() {
        guard let plan = pendingModUpdatePlan else {
            modUpdateTarget = nil
            return
        }
        pendingModUpdatePlan = nil
        modUpdateTarget = nil
        Task { await modUpdateService.discard(plan) }
    }

    func restorePreviousModVersion(_ record: ModUpdateHistoryRecord) async {
        isUpdatingMod = true
        defer { isUpdatingMod = false }
        do {
            let restored = try await modUpdateService.restore(record) { progress in
                await MainActor.run { self.modUpdateProgress = progress }
            }
            loadPersistedModUpdateHistory()
            readinessReport = nil
            await refreshMods()
            statusMessage = "Restored the previous version of \(restored.modName)"
        } catch {
            loadPersistedModUpdateHistory()
            await refreshMods()
            showError(error)
        }
    }

    private func loadPersistedModUpdateHistory() {
        do {
            let payload = try modUpdateHistoryService.load()
            modUpdateHistory = payload.records
            modUpdateProvenance = payload.provenanceByUUID
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

        let modsFolder = FileLocations.modsFolder
        let importResult = await Task.detached(priority: .userInitiated) {
            ModImportService().importMods(from: urls, to: modsFolder)
        }.value

        if !importResult.errors.isEmpty {
            errorMessage = importResult.errors.joined(separator: "\n")
            showError = true
        }

        guard importResult.importedCount > 0 else {
            if !importResult.alreadyPresentFilenames.isEmpty {
                statusMessage = "Selected mod file(s) are already in the Mods folder"
            }
            return
        }

        // Capture the latest UI state after file work finishes in case an archive import yielded.
        let currentActiveMods = activeMods
        let currentInactiveMods = inactiveMods
        let currentHasUnsavedChanges = hasUnsavedChanges

        let newMods: [ModInfo]
        do {
            // Importing changes the files on disk, but it must not reload activation state from
            // modsettings.lsx: the in-memory load order may contain unsaved user changes.
            let service = discoveryService
            let discoveredMods = try await Task.detached(priority: .userInitiated) {
                try service.discoverCanonicalMods()
            }.value
            let merged = ImportDiscoveryMerger.merge(
                previousActive: currentActiveMods,
                previousInactive: currentInactiveMods,
                hadUnsavedChanges: currentHasUnsavedChanges,
                discovered: discoveredMods
            )
            activeMods = merged.active.map { inferCategory(for: $0) }
            inactiveMods = merged.inactive.map { inferCategory(for: $0) }
            hasUnsavedChanges = merged.hasUnsavedChanges
            await refreshDuplicateGroups()

            let newUUIDs = Set(merged.newMods.map(\.uuid))
            newMods = inactiveMods.filter { newUUIDs.contains($0.uuid) }
            runValidation()
        } catch {
            showError(error)
            return
        }

        if !importResult.replacedFilenames.isEmpty {
            statusMessage = "Imported \(importResult.importedCount) file(s) (replaced \(importResult.replacedFilenames.count) existing)"
        } else {
            statusMessage = "Imported \(importResult.importedCount) file(s)"
        }

        if !newMods.isEmpty {
            lastImportedMods = newMods
            showImportActivation = true
        }
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
                try await Task.detached(priority: .userInitiated) {
                    try FileManager.default.createDirectory(
                        at: extractFolder,
                        withIntermediateDirectories: true
                    )
                    try PakReader.extractAll(from: pakURL, to: extractFolder)
                }.value
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
        guard !missing.isEmpty else { return 0 }
        saveSnapshot()
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
        saveSnapshot()
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
        saveSnapshot()
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
        saveSnapshot()
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
        saveSnapshot()

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
        readinessReport = nil
        warnings = validationService.validate(
            activeMods: activeMods,
            inactiveMods: inactiveMods,
            seStatus: seStatus,
            seWasPreviouslyDeployed: seService.wasDeployed(),
            loadOrderRules: loadOrderRules
        )
    }

    // MARK: - Duplicate Resolution

    /// Groups all mods by UUID where more than one mod shares the same UUID.
    func detectDuplicateGroups() {
        Task { await refreshDuplicateGroups() }
    }

    private func refreshDuplicateGroups() async {
        do {
            let service = discoveryService
            let physicalMods = try await Task.detached(priority: .userInitiated) {
                try service.discoverMods()
            }.value
            duplicateGroups = Dictionary(grouping: physicalMods) {
                ModIdentity.comparisonKey($0.uuid)
            }.values
                .filter { $0.count > 1 }
                .map { $0.sorted {
                    ($0.pakFileName ?? "").localizedCaseInsensitiveCompare(
                        $1.pakFileName ?? ""
                    ) == .orderedAscending
                } }
                .sorted { ($0.first?.name ?? "") < ($1.first?.name ?? "") }
            showDuplicateResolver = !duplicateGroups.isEmpty
        } catch {
            showError(error)
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

        switch loadOrderSolver.solve(
            mods: nonBase,
            rules: loadOrderRules,
            mode: .dependenciesOnly
        ) {
        case .ordered(let sorted):
            saveSnapshot()
            activeMods = base + sorted
            hasUnsavedChanges = true
            runValidation()
            statusMessage = "Mods sorted by dependencies and persistent rules"
        case .conflict(let conflict):
            errorMessage = "Cannot sort: \(conflict.message)"
            showError = true
        }
    }

    /// Smart sort: globally satisfies hard dependencies/rules and uses category as a soft priority.
    func smartSort() {
        let base = activeMods.filter { $0.isBasicGameModule }
        let nonBase = activeMods.filter { !$0.isBasicGameModule }

        switch loadOrderSolver.solve(
            mods: nonBase,
            rules: loadOrderRules,
            mode: .smart
        ) {
        case .ordered(let sorted):
            saveSnapshot()
            activeMods = base + sorted
            hasUnsavedChanges = true
            runValidation()

            let categorized = nonBase.filter { $0.category != nil }.count
            statusMessage = "Smart sort complete (\(categorized)/\(nonBase.count) categorized; rules applied)"
        case .conflict(let conflict):
            errorMessage = "Cannot smart sort: \(conflict.message)"
            showError = true
        }
    }

    // MARK: - Persistent Load-Order Rules

    private func loadPersistedLoadOrderRules() {
        do {
            loadOrderRules = try loadOrderRuleService.loadRules()
        } catch {
            showError(error)
        }
    }

    @discardableResult
    func addLoadOrderRule(
        kind: LoadOrderRule.Kind,
        sourceUUID: String,
        targetUUID: String? = nil,
        position: Int? = nil
    ) -> Bool {
        let rule = LoadOrderRule(
            kind: kind,
            sourceUUID: sourceUUID,
            targetUUID: targetUUID,
            position: position
        )
        do {
            try loadOrderRuleService.validate(rule)
        } catch {
            showError(error)
            return false
        }

        let previous = loadOrderRules
        if let index = loadOrderRules.firstIndex(where: {
            $0.kind == rule.kind &&
                $0.sourceUUID == rule.sourceUUID &&
                $0.targetUUID == rule.targetUUID &&
                $0.position == rule.position &&
                $0.profileID == nil
        }) {
            loadOrderRules[index].isEnabled = true
            loadOrderRules[index].updatedAt = Date()
        } else {
            loadOrderRules.append(rule)
        }

        guard persistLoadOrderRules(orRestore: previous) else { return false }
        runValidation()
        statusMessage = "Saved persistent load-order rule"
        return true
    }

    func setLoadOrderRuleEnabled(_ rule: LoadOrderRule, enabled: Bool) {
        guard let index = loadOrderRules.firstIndex(where: { $0.id == rule.id }) else { return }
        let previous = loadOrderRules
        loadOrderRules[index].isEnabled = enabled
        loadOrderRules[index].updatedAt = Date()
        guard persistLoadOrderRules(orRestore: previous) else { return }
        runValidation()
    }

    func deleteLoadOrderRule(_ rule: LoadOrderRule) {
        let previous = loadOrderRules
        loadOrderRules.removeAll { $0.id == rule.id }
        guard persistLoadOrderRules(orRestore: previous) else { return }
        runValidation()
        statusMessage = "Deleted load-order rule"
    }

    func loadOrderRules(for mod: ModInfo) -> [LoadOrderRule] {
        let uuid = ModIdentity.comparisonKey(mod.uuid)
        return loadOrderRules.filter {
            $0.sourceUUID == uuid || $0.targetUUID == uuid
        }
    }

    func displayName(forModUUID uuid: String) -> String {
        let key = ModIdentity.comparisonKey(uuid)
        return (activeMods + inactiveMods).first {
            ModIdentity.comparisonKey($0.uuid) == key
        }?.name ?? uuid
    }

    func isInstalledModUUID(_ uuid: String) -> Bool {
        let key = ModIdentity.comparisonKey(uuid)
        return (activeMods + inactiveMods).contains {
            ModIdentity.comparisonKey($0.uuid) == key
        }
    }

    private func persistLoadOrderRules(orRestore previous: [LoadOrderRule]) -> Bool {
        do {
            try loadOrderRuleService.saveRules(loadOrderRules)
            return true
        } catch {
            loadOrderRules = previous
            showError(error)
            return false
        }
    }

    /// Set a user category override for a mod and re-infer.
    func setCategoryOverride(_ category: ModCategory?, for mod: ModInfo) {
        guard categoryService.setOverride(category, for: mod.uuid) else {
            reportPersistenceFailure("category override")
            return
        }
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
            hasUnsavedChanges = false
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
    /// Supports modern binary meta.lsf metadata and legacy modsettings.lsx saves.
    func importFromSaveFile(url: URL) async {
        saveSnapshot()
        do {
            let save = try await saveGameScanner.inspectSave(at: url)
            guard save.isReadable else {
                errorMessage = save.readError ?? "The save metadata could not be read."
                showError = true
                return
            }

            // Reconstruct active/inactive lists from save data.
            let allMods = activeMods + inactiveMods
            var newActive: [ModInfo] = []
            var usedUUIDs: Set<String> = []

            for entry in save.mods {
                if let mod = allMods.first(where: { $0.uuid == entry.uuid }) {
                    newActive.append(mod)
                    usedUUIDs.insert(entry.uuid)
                } else {
                    // Create placeholder for mods we don't have on disk
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
                    usedUUIDs.insert(entry.uuid)
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
        saveSnapshot()
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
        if let url, !url.isEmpty, !NexusURLImportService().isNexusURL(url) {
            errorMessage = "Enter a valid BG3 Nexus Mods URL (https://www.nexusmods.com/baldursgate3/mods/…)."
            showError = true
            return
        }
        guard nexusURLService.setURL(url, for: mod.uuid) else {
            reportPersistenceFailure("Nexus URL")
            return
        }
        objectWillChange.send()
    }

    /// Bulk-set Nexus URLs from an import operation.
    func bulkSetNexusURLs(_ urls: [String: String]) {
        guard nexusURLService.bulkSetURLs(urls) else {
            reportPersistenceFailure("Nexus URLs")
            return
        }
        objectWillChange.send()
        statusMessage = "Set Nexus URLs for \(urls.count) mod(s)"
    }

    // MARK: - Mod Notes

    /// Set or clear a user note for a mod.
    func setModNote(_ text: String?, for mod: ModInfo) {
        guard modNotesService.setNote(text, for: mod.uuid) else {
            reportPersistenceFailure("mod note")
            return
        }
        objectWillChange.send()
    }

    // MARK: - Nexus Updates

    /// Check all mods with Nexus URLs for available updates.
    func checkForNexusUpdates() async {
        guard nexusAPIService.apiKey != nil else {
            errorMessage = "No Nexus Mods API key configured. Set one in Settings > General > Nexus Mods."
            showError = true
            return
        }

        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }

        do {
            let candidates = (activeMods + inactiveMods).compactMap { mod -> NexusUpdateCandidate? in
                guard !isNexusCheckDisabled(for: mod.uuid) else { return nil }
                guard let url = nexusURLService.url(for: mod.uuid) else { return nil }
                return NexusUpdateCandidate(
                    modUUID: mod.uuid,
                    installedVersion: mod.version.description,
                    nexusURL: url
                )
            }
            guard !candidates.isEmpty else {
                nexusUpdateResults = [:]
                let disabledCount = nexusUpdatePreferences.values.filter(\.checksDisabled).count
                statusMessage = disabledCount > 0
                    ? "No enabled Nexus-linked mods to check (\(disabledCount) disabled)"
                    : "No mods have Nexus URLs to check"
                return
            }
            let report = try await nexusAPIService.checkForUpdates(
                candidates: candidates
            ) { checked, total in
                await self.setUpdateCheckProgress(checked: checked, total: total)
            }
            nexusUpdateResults = report.results
            readinessReport = nil
            if !report.cachePersisted {
                errorMessage = "Nexus results were checked but could not be saved to the local cache."
                showError = true
            }
            let actionable = report.results.values.filter { !isNexusResultSuppressed($0) }
            let updateCount = actionable.filter(\.hasUpdate).count
            let differenceCount = actionable.filter(\.versionDiffers).count
            let ignoredCount = report.results.values.filter(isNexusVersionIgnored).count
            if !report.isComplete {
                var details: [String] = []
                if report.rateLimited { details.append("rate limited") }
                if report.failedCount > 0 { details.append("\(report.failedCount) failed") }
                if report.skippedCount > 0 { details.append("\(report.skippedCount) invalid URL") }
                statusMessage = "Update check incomplete (\(details.joined(separator: ", ")))"
            } else if updateCount > 0 {
                statusMessage = "Found \(updateCount) mod update(s) available"
            } else if differenceCount > 0 {
                statusMessage = "Nexus versions differ for \(differenceCount) mod(s)"
            } else if ignoredCount > 0 {
                statusMessage = "No actionable Nexus updates (\(ignoredCount) version difference(s) ignored)"
            } else {
                statusMessage = "All checked mods are up to date"
            }
        } catch {
            showError(error)
        }
    }

    private func setUpdateCheckProgress(checked: Int, total: Int) {
        updateCheckProgress = (checked, total)
    }

    /// Whether a mod has an available update on Nexus.
    func hasNexusUpdate(for mod: ModInfo) -> Bool {
        guard let result = nexusUpdateInfo(for: mod) else { return false }
        return result.hasUpdate && !isNexusResultSuppressed(result)
    }

    /// Get the full update info for a mod, if available.
    func nexusUpdateInfo(for mod: ModInfo) -> NexusUpdateResult? {
        nexusUpdateResults[ModIdentity.comparisonKey(mod.uuid)]
    }

    var nexusAttentionResults: [NexusUpdateResult] {
        nexusUpdateResults.values.filter {
            ($0.hasUpdate || $0.versionDiffers) && !isNexusResultSuppressed($0)
        }
    }

    var nexusAttentionCount: Int { nexusAttentionResults.count }

    func isNexusCheckDisabled(for modUUID: String) -> Bool {
        nexusUpdatePreferences[ModIdentity.comparisonKey(modUUID)]?.checksDisabled == true
    }

    func isNexusVersionIgnored(_ result: NexusUpdateResult) -> Bool {
        guard result.hasUpdate || result.versionDiffers else { return false }
        guard let preference = nexusUpdatePreferences[ModIdentity.comparisonKey(result.modUUID)],
              !preference.checksDisabled else { return false }
        return preference.suppresses(result)
    }

    func isNexusResultSuppressed(_ result: NexusUpdateResult) -> Bool {
        nexusUpdatePreferences[ModIdentity.comparisonKey(result.modUUID)]?.suppresses(result) == true
    }

    func ignoreNexusVersion(_ result: NexusUpdateResult) {
        persistNexusUpdatePreferences(
            nexusUpdatePreferenceService.ignoring(result, in: nexusUpdatePreferences),
            successMessage: "Ignored Nexus version \(result.latestVersion) for \(result.latestName)"
        )
    }

    func stopIgnoringNexusVersion(for modUUID: String) {
        persistNexusUpdatePreferences(
            nexusUpdatePreferenceService.clearingIgnoredVersion(
                for: modUUID,
                in: nexusUpdatePreferences
            ),
            successMessage: "Nexus version alerts re-enabled"
        )
    }

    func setNexusChecksDisabled(_ disabled: Bool, for mod: ModInfo) {
        persistNexusUpdatePreferences(
            nexusUpdatePreferenceService.settingChecksDisabled(
                disabled,
                for: mod.uuid,
                in: nexusUpdatePreferences
            ),
            successMessage: disabled
                ? "Disabled Nexus checks for \(mod.name)"
                : "Enabled Nexus checks for \(mod.name)"
        )
    }

    private func loadPersistedNexusUpdatePreferences() {
        do {
            nexusUpdatePreferences = try nexusUpdatePreferenceService.loadPreferences()
        } catch {
            showError(error)
        }
    }

    private func persistNexusUpdatePreferences(
        _ updated: [String: NexusUpdatePreference],
        successMessage: String
    ) {
        let previous = nexusUpdatePreferences
        nexusUpdatePreferences = updated
        do {
            try nexusUpdatePreferenceService.savePreferences(updated)
            readinessReport = nil
            statusMessage = successMessage
        } catch {
            nexusUpdatePreferences = previous
            showError(error)
        }
    }

    // MARK: - Error Handling

    private func showError(_ error: Error) {
        errorMessage = error.localizedDescription
        showError = true
        statusMessage = "Error: \(error.localizedDescription)"
    }

    private func reportPersistenceFailure(_ item: String) {
        errorMessage = "Could not save the \(item). The previous value was kept."
        showError = true
        statusMessage = "Persistence error: \(item) was not saved"
    }
}

// MARK: - Import Discovery Merge

/// Merges a post-import disk scan into the current in-memory load order.
///
/// Existing activation choices and active ordering are authoritative because they may not have
/// been saved to modsettings.lsx yet. Newly discovered mods always start inactive.
enum ImportDiscoveryMerger {
    struct Result {
        let active: [ModInfo]
        let inactive: [ModInfo]
        let newMods: [ModInfo]
        let hasUnsavedChanges: Bool
    }

    static func merge(
        previousActive: [ModInfo],
        previousInactive: [ModInfo],
        hadUnsavedChanges: Bool,
        discovered: [ModInfo]
    ) -> Result {
        let previouslyKnownUUIDs = Set((previousActive + previousInactive).map(\.uuid))
        let discoveredByUUID = Dictionary(
            discovered.map { ($0.uuid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var accountedUUIDs = Set<String>()

        var active = previousActive.compactMap { previousMod -> ModInfo? in
            guard accountedUUIDs.insert(previousMod.uuid).inserted else { return nil }
            // Keep an active entry even if its PAK is temporarily missing; importing another mod
            // should never silently remove or deactivate the user's current load-order entries.
            return discoveredByUUID[previousMod.uuid] ?? previousMod
        }

        var inactive = previousInactive.compactMap { previousMod -> ModInfo? in
            guard !accountedUUIDs.contains(previousMod.uuid),
                  let discoveredMod = discoveredByUUID[previousMod.uuid]
            else { return nil }
            accountedUUIDs.insert(previousMod.uuid)
            return discoveredMod
        }

        var newMods: [ModInfo] = []
        for mod in discovered where !previouslyKnownUUIDs.contains(mod.uuid) {
            guard accountedUUIDs.insert(mod.uuid).inserted else { continue }
            if mod.isBasicGameModule {
                active.insert(mod, at: 0)
            } else {
                newMods.append(mod)
            }
        }
        newMods.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        inactive.append(contentsOf: newMods)
        // A previously known required component may have been in the inactive pane in
        // an older app state. Promote its refreshed representation unconditionally.
        for module in discovered.filter(\.isBasicGameModule) where !active.contains(where: {
            ModIdentity.comparisonKey($0.uuid) == ModIdentity.comparisonKey(module.uuid)
        }) {
            active.insert(module, at: 0)
        }
        inactive.removeAll(where: \.isBasicGameModule)

        return Result(
            active: active,
            inactive: inactive,
            newMods: newMods,
            hasUnsavedChanges: hadUnsavedChanges
        )
    }
}

private enum SaveError: Error, LocalizedError {
    case unlockFailed

    var errorDescription: String? {
        switch self {
        case .unlockFailed:
            return "Could not unlock modsettings.lsx for saving"
        }
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
