// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Filter option for Script Extender requirement.
enum SEFilterOption: String, CaseIterable {
    case all = "All"
    case seOnly = "SE Required"
    case nonSEOnly = "No SE"
}

/// Filter option for validation warnings.
enum WarningFilterOption: String, CaseIterable {
    case all = "All"
    case withWarnings = "Has Warnings"
    case withoutWarnings = "No Warnings"
}

/// Sort options for the inactive mod list.
enum InactiveSortOption: String, CaseIterable {
    case name = "Name"
    case author = "Author"
    case category = "Category"
    case fileDate = "File Date"
    case fileSize = "File Size"
}

/// Main mod management view with active (load order) and inactive mod lists.
struct ModListView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var warningsExpanded = false
    @State private var selectedCategories: Set<ModCategory> = []
    @State private var showUncategorized = true
    @AppStorage("inactiveSortOption") private var inactiveSortOptionRaw: String = InactiveSortOption.name.rawValue
    @AppStorage("inactiveSortAscending") private var inactiveSortAscending: Bool = true
    @State private var showFilterPopover = false
    @State private var filterSERequired: SEFilterOption = .all
    @State private var filterHasWarnings: WarningFilterOption = .all
    @State private var filterMetadataSources: Set<String> = []

    private var currentSortOption: InactiveSortOption {
        InactiveSortOption(rawValue: inactiveSortOptionRaw) ?? .name
    }

    /// Whether any advanced filter is active.
    private var isAdvancedFilterActive: Bool {
        filterSERequired != .all || filterHasWarnings != .all || !filterMetadataSources.isEmpty
    }

    /// Count of active advanced filters (for badge display).
    private var advancedFilterCount: Int {
        var count = 0
        if filterSERequired != .all { count += 1 }
        if filterHasWarnings != .all { count += 1 }
        if !filterMetadataSources.isEmpty { count += 1 }
        return count
    }

    var body: some View {
        HSplitView {
            // Left: Active + Inactive mod lists
            VStack(spacing: 0) {
                // Primary action bar
                actionBar
                Divider()

                // Category filter chips
                if isCategoryFilterActive || isAdvancedFilterActive || (appState.activeMods.count + appState.inactiveMods.count) > 20 {
                    categoryFilterBar
                    Divider()
                }

                // Warnings banner
                if !appState.warnings.isEmpty {
                    warningsBanner
                }

                // Multi-selection action bar
                if appState.selectedModIDs.count > 1 {
                    multiSelectActionBar
                }

                activeModsSection
                Divider()
                inactiveModsSection
            }
            .frame(minWidth: 350)

            // Right: Detail panel
            modDetailPanel
                .frame(minWidth: 280, idealWidth: 320)
        }
        .searchable(text: $searchText, prompt: "Filter mods...")
        .onChange(of: appState.selectedModIDs) { newSelection in
            // Keep selectedModID in sync for detail panel display
            if newSelection.count == 1 {
                appState.selectedModID = newSelection.first
            } else if newSelection.isEmpty {
                appState.selectedModID = nil
            }
        }
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                Task { await appState.saveModSettings() }
            } label: {
                HStack(spacing: 4) {
                    Label("Save Load Order", systemImage: "arrow.down.doc.fill")
                    if appState.hasUnsavedChanges {
                        Circle()
                            .fill(Color.unsavedDot)
                            .frame(width: 6, height: 6)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .disabled(appState.isLoading)
            .help(appState.hasUnsavedChanges
                ? "Save mod order to modsettings.lsx (unsaved changes)"
                : "Save mod order to modsettings.lsx")

            Button {
                Task { await appState.refreshAll() }
            } label: {
                Label("Rescan Folder", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(appState.isLoading)
            .help("Rescan mods folder")

            Button {
                Task { await appState.checkForNexusUpdates() }
            } label: {
                if appState.isCheckingForUpdates {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Label("Check Updates", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(appState.isCheckingForUpdates || appState.nexusAPIService.apiKey == nil)
            .help(appState.nexusAPIService.apiKey == nil
                ? "Set a Nexus Mods API key in Settings to enable update checking"
                : "Check Nexus Mods for available updates")

            Spacer()

            Button {
                Task { await appState.launchGame() }
            } label: {
                Label("Launch BG3", systemImage: "play.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(!appState.isGameInstalled)
            .help("Launch Baldur's Gate 3")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Multi-Select Action Bar

    private var multiSelectActionBar: some View {
        let selectedActiveCount = appState.activeMods.filter {
            appState.selectedModIDs.contains($0.uuid) && !$0.isBasicGameModule
        }.count
        let selectedInactiveCount = appState.inactiveMods.filter {
            appState.selectedModIDs.contains($0.uuid)
        }.count

        return HStack(spacing: 8) {
            Text("\(appState.selectedModIDs.count) selected")
                .font(.caption.bold())

            Spacer()

            if selectedInactiveCount > 0 {
                Button("Activate \(selectedInactiveCount)") {
                    appState.activateSelectedMods()
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .help("Activate all selected inactive mods")
            }

            if selectedActiveCount > 0 {
                Button("Deactivate \(selectedActiveCount)") {
                    appState.deactivateSelectedMods()
                }
                .font(.caption2)
                .buttonStyle(.bordered)
                .help("Deactivate all selected active mods")
            }

            Button("Clear") {
                appState.selectedModIDs.removeAll()
            }
            .font(.caption2)
            .buttonStyle(.plain)
            .help("Clear multi-selection")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.bgSelected)
    }

    // MARK: - Warnings Banner

    private var warningsBanner: some View {
        let criticalCount = appState.warnings.filter { $0.severity == .critical }.count
        let warningCount = appState.warnings.filter { $0.severity == .warning }.count

        return VStack(spacing: 0) {
            // Summary bar (always visible when warnings exist)
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { warningsExpanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    if criticalCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                            Text("\(criticalCount) critical")
                                .foregroundStyle(.red)
                        }
                    }
                    if warningCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.yellow)
                            Text("\(warningCount) warning\(warningCount == 1 ? "" : "s")")
                        }
                    }

                    Spacer()

                    Image(systemName: warningsExpanded ? "chevron.up" : "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(criticalCount > 0 ? Color.severityCriticalBg : Color.severityWarningBg)
            }
            .buttonStyle(.plain)
            .help("Show or hide validation warnings")

            // Expanded warning list
            if warningsExpanded {
                warningsDetailList
            }

            Divider()
        }
    }

    private var warningsDetailList: some View {
        let grouped = Dictionary(grouping: appState.warnings, by: \.category)
        let sortedCategories = grouped.keys.sorted { a, b in
            let maxA = grouped[a]!.max(by: { $0.severity < $1.severity })?.severity.rawValue ?? 0
            let maxB = grouped[b]!.max(by: { $0.severity < $1.severity })?.severity.rawValue ?? 0
            return maxA > maxB
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(sortedCategories, id: \.self) { category in
                    let warnings = grouped[category]!
                    let maxSeverity = warnings.max(by: { $0.severity < $1.severity })?.severity ?? .info

                    HStack(alignment: .top, spacing: 0) {
                        // Left severity strip
                        RoundedRectangle(cornerRadius: 2)
                            .fill(maxSeverity.color)
                            .frame(width: 3)

                        VStack(alignment: .leading, spacing: 4) {
                            // Category header
                            HStack(spacing: 4) {
                                Text(category.rawValue)
                                    .font(.caption.bold())
                                Text("(\(warnings.count))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.bottom, 2)

                            ForEach(warnings) { warning in
                                warningRow(warning)
                            }
                        }
                        .padding(.leading, 8)
                        .padding(.vertical, 4)
                    }
                    .padding(.horizontal, 12)
                }
            }
        }
        .frame(maxHeight: 150)
    }

    private func warningRow(_ warning: ModWarning) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: warning.severity.icon)
                .foregroundStyle(warning.severity.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(warning.message)
                    .font(.caption)
                    .fontWeight(.medium)
                if !warning.detail.isEmpty {
                    Text(warning.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()

            warningActionButton(warning)
        }
    }

    @ViewBuilder
    private func warningActionButton(_ warning: ModWarning) -> some View {
        if case .autoSort = warning.suggestedAction {
            Button("Auto-Sort") {
                appState.autoSortByDependencies()
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            .help("Sort mods by dependency order")
        }

        if warning.category == .duplicateUUID {
            Button("Resolve...") {
                appState.detectDuplicateGroups()
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            .help("Open duplicate mod resolver")
        }

        if warning.category == .conflictingMods,
           case .deactivateMod(let uuid) = warning.suggestedAction,
           let conflictMod = appState.activeMods.first(where: { $0.uuid == uuid }) {
            Button("Deactivate \(conflictMod.name)") {
                appState.deactivateMod(conflictMod)
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            .help("Deactivate the conflicting mod to resolve this conflict. You can re-activate it later from the inactive list.")
        }

        if case .deleteModCrashSanityCheck = warning.suggestedAction {
            Button("Delete Folder") {
                appState.deleteModCrashSanityCheckIfNeeded()
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            .help("Delete the ModCrashSanityCheck directory to prevent the game from deactivating your mods on launch")
        }

        if case .activateDependencies(let modUUID) = warning.suggestedAction {
            Button("Activate Deps") {
                if let mod = appState.activeMods.first(where: { $0.uuid == modUUID }) {
                    let count = appState.activateMissingDependencies(for: mod)
                    appState.statusMessage = "Activated \(count) missing dependency(ies)"
                }
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            .help("Activate the missing dependencies from the inactive mod list")
        }

        if case .restoreModSettings = warning.suggestedAction {
            Button("Restore Backup") {
                Task { await appState.restoreFromLatestBackup() }
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            .help("Restore modsettings.lsx from the most recent backup to recover your load order")
        }

        if case .viewSEStatus = warning.suggestedAction {
            Button("View SE Status") {
                appState.navigateToSidebarItem = "scriptExtender"
            }
            .font(.caption2)
            .buttonStyle(.bordered)
            .help("Open the Script Extender status page to check installation and re-deploy")
        }
    }

    // MARK: - Active Mods

    private var activeModsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Active Mods (\(appState.activeMods.count))", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Button {
                    appState.smartSort()
                } label: {
                    Label("Smart Sort", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Sort mods by community load order tiers (Framework → Gameplay → Content → Visual → Late Loader), then by dependencies within each tier")

                Menu {
                    Button("Activate All") { appState.activateAll() }
                        .help("Move all inactive mods into the active load order")
                    Button("Deactivate All") { appState.deactivateAll() }
                        .help("Move all active mods (except the base game module) to the inactive list")
                    Divider()
                    Button("Activate Missing Dependencies") {
                        let count = appState.activateAllMissingDependencies()
                        if count == 0 {
                            appState.statusMessage = "No missing dependencies found in inactive mods"
                        }
                    }
                    .help("Find and activate all missing dependencies from the inactive mod list")
                    Divider()
                    Button("Smart Sort (Tier + Dependencies)") { appState.smartSort() }
                        .help("Sort by the 5-tier community convention, then apply dependency ordering within each tier. Uncategorized mods are placed in the middle.")
                    Button("Sort by Dependencies Only") { appState.autoSortByDependencies() }
                        .help("Sort using only declared mod dependencies (topological sort). Does not consider category tiers.")
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Bulk actions: activate/deactivate all mods, or sort the active load order")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(selection: $appState.selectedModIDs) {
                ForEach(filteredActiveMods) { mod in
                    ModRowView(mod: mod, isActive: true)
                        .tag(mod.uuid)
                        .moveDisabled(!searchText.isEmpty || isCategoryFilterActive || isAdvancedFilterActive)
                        .onTapGesture(count: 2) {
                            if !mod.isBasicGameModule {
                                appState.deactivateMod(mod)
                            }
                        }
                        .contextMenu {
                            if !mod.isBasicGameModule {
                                Button("Deactivate") { appState.deactivateMod(mod) }
                            }
                            if appState.selectedModIDs.count > 1 {
                                let count = appState.activeMods.filter {
                                    appState.selectedModIDs.contains($0.uuid) && !$0.isBasicGameModule
                                }.count
                                if count > 0 {
                                    Button("Deactivate \(count) Selected") {
                                        appState.deactivateSelectedMods()
                                    }
                                }
                            }

                            if !mod.isBasicGameModule {
                                Divider()
                                Button("Move to Top") {
                                    appState.moveModToTop(mod)
                                }
                                .help("Move this mod to the top of the load order (after the base game module)")
                                Button("Move to Bottom") {
                                    appState.moveModToBottom(mod)
                                }
                                .help("Move this mod to the end of the load order")
                            }

                            Divider()
                            Button("Open on Nexus Mods") {
                                appState.openNexusPage(for: mod)
                            }
                            .help(appState.nexusURLService.url(for: mod.uuid) != nil
                                  ? "Open this mod's Nexus Mods page"
                                  : "Search for this mod on Nexus Mods")
                            Button("Copy Mod Info") {
                                appState.copyModInfo(mod)
                            }
                            .help("Copy mod name, author, version, UUID, and other details to the clipboard")
                            Button("Copy UUID") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(mod.uuid, forType: .string)
                            }
                            Button(appState.modNotesService.note(for: mod.uuid) != nil ? "Edit Note" : "Add Note") {
                                appState.selectedModID = mod.uuid
                            }
                            .help("Add or edit a personal note for this mod")
                            if let filePath = mod.pakFilePath {
                                Divider()
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([filePath])
                                }
                                .help("Show this mod's PAK file in Finder")
                                Button("Extract to Folder...") {
                                    appState.extractMod(mod)
                                }
                            }
                        }
                }
                .onMove { source, destination in
                    appState.moveActiveMod(from: source, to: destination)
                }
                .onInsert(of: [.utf8PlainText]) { index, providers in
                    handleActiveListInsert(at: index, providers: providers)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    // MARK: - Inactive Mods

    private var inactiveModsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Inactive Mods (\(appState.inactiveMods.count))", systemImage: "xmark.circle")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()

                Button {
                    inactiveSortAscending.toggle()
                } label: {
                    Image(systemName: inactiveSortAscending ? "arrow.up" : "arrow.down")
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .help(inactiveSortAscending ? "Currently ascending — click to sort descending" : "Currently descending — click to sort ascending")

                Picker("Sort by", selection: $inactiveSortOptionRaw) {
                    ForEach(InactiveSortOption.allCases, id: \.rawValue) { option in
                        Text(option.rawValue).tag(option.rawValue)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .controlSize(.small)
                .help("Choose how to sort the inactive mod list")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(selection: $appState.selectedModIDs) {
                ForEach(filteredInactiveMods) { mod in
                    ModRowView(mod: mod, isActive: false)
                        .tag(mod.uuid)
                        .onTapGesture(count: 2) {
                            appState.activateMod(mod)
                        }
                        .draggable(mod.uuid)
                        .contextMenu {
                            Button("Activate") { appState.activateMod(mod) }
                            if appState.selectedModIDs.count > 1 {
                                let count = appState.inactiveMods.filter {
                                    appState.selectedModIDs.contains($0.uuid)
                                }.count
                                if count > 0 {
                                    Button("Activate \(count) Selected") {
                                        appState.activateSelectedMods()
                                    }
                                }
                            }
                            Divider()
                            Button("Open on Nexus Mods") {
                                appState.openNexusPage(for: mod)
                            }
                            .help(appState.nexusURLService.url(for: mod.uuid) != nil
                                  ? "Open this mod's Nexus Mods page"
                                  : "Search for this mod on Nexus Mods")
                            Button("Copy Mod Info") {
                                appState.copyModInfo(mod)
                            }
                            .help("Copy mod name, author, version, UUID, and other details to the clipboard")
                            Button("Copy UUID") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(mod.uuid, forType: .string)
                            }
                            Button(appState.modNotesService.note(for: mod.uuid) != nil ? "Edit Note" : "Add Note") {
                                appState.selectedModID = mod.uuid
                            }
                            .help("Add or edit a personal note for this mod")
                            if let filePath = mod.pakFilePath {
                                Divider()
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([filePath])
                                }
                                .help("Show this mod's PAK file in Finder")
                                Button("Extract to Folder...") {
                                    appState.extractMod(mod)
                                }
                                Divider()
                                Button("Delete from Disk...", role: .destructive) {
                                    appState.requestDeleteMod(mod)
                                }
                                .help("Permanently remove this mod's PAK file from the Mods folder")
                            }
                            if appState.selectedModIDs.count > 1 {
                                let deleteCount = appState.inactiveMods.filter {
                                    appState.selectedModIDs.contains($0.uuid) && $0.pakFilePath != nil && !$0.isBasicGameModule
                                }.count
                                if deleteCount > 0 {
                                    Button("Delete \(deleteCount) Selected from Disk...", role: .destructive) {
                                        appState.requestDeleteSelectedMods()
                                    }
                                    .help("Permanently remove the selected mods' PAK files from the Mods folder")
                                }
                            }
                        }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var modDetailPanel: some View {
        if appState.selectedModIDs.count > 1 {
            multiSelectDetailPanel
        } else if let mod = appState.selectedMod {
            ModDetailView(mod: mod)
        } else {
            VStack {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Select a mod to view details")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var multiSelectDetailPanel: some View {
        let selectedActive = appState.activeMods.filter { appState.selectedModIDs.contains($0.uuid) }
        let selectedInactive = appState.inactiveMods.filter { appState.selectedModIDs.contains($0.uuid) }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(appState.selectedModIDs.count) Mods Selected")
                    .font(.title2.bold())

                if !selectedActive.isEmpty {
                    Text("\(selectedActive.count) active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if !selectedInactive.isEmpty {
                    Text("\(selectedInactive.count) inactive")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                ForEach(selectedActive + selectedInactive) { mod in
                    HStack {
                        Image(systemName: selectedActive.contains(where: { $0.uuid == mod.uuid })
                              ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedActive.contains(where: { $0.uuid == mod.uuid })
                                             ? .green : .secondary)
                        VStack(alignment: .leading) {
                            Text(mod.name)
                                .font(.body.bold())
                            if mod.author != "Unknown" {
                                Text(mod.author)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Category Filter Bar

    /// Whether any category filter is actively narrowing results.
    private var isCategoryFilterActive: Bool {
        !selectedCategories.isEmpty || !showUncategorized
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ModCategory.allCases, id: \.self) { category in
                    Button {
                        if selectedCategories.contains(category) {
                            selectedCategories.remove(category)
                        } else {
                            selectedCategories.insert(category)
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: category.icon)
                                .font(.caption2)
                            Text(category.displayName)
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            selectedCategories.contains(category)
                                ? category.color.opacity(0.25)
                                : Color.clear,
                            in: Capsule()
                        )
                        .overlay(
                            Capsule()
                                .strokeBorder(
                                    selectedCategories.contains(category)
                                        ? category.color
                                        : Color.chipBorder,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .help(category.tooltip)
                }

                Button {
                    showUncategorized.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "questionmark.square")
                            .font(.caption2)
                        Text("Uncategorized")
                            .font(.caption)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        showUncategorized
                            ? Color.chipBgUncategorized
                            : Color.clear,
                        in: Capsule()
                    )
                    .overlay(
                        Capsule()
                            .strokeBorder(
                                showUncategorized
                                    ? Color.chipBorderActive
                                    : Color.chipBorder,
                                lineWidth: 1
                            )
                    )
                }
                .buttonStyle(.plain)
                .help("Show or hide mods without a category assignment")

                if isCategoryFilterActive || isAdvancedFilterActive {
                    Button("Clear") {
                        selectedCategories.removeAll()
                        showUncategorized = true
                        filterSERequired = .all
                        filterHasWarnings = .all
                        filterMetadataSources.removeAll()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reset all filters")
                }

                Divider()
                    .frame(height: 16)

                Button {
                    showFilterPopover.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isAdvancedFilterActive
                            ? "line.3.horizontal.decrease.circle.fill"
                            : "line.3.horizontal.decrease.circle")
                            .font(.caption)
                        if advancedFilterCount > 0 {
                            Text("\(advancedFilterCount)")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .frame(width: 16, height: 16)
                                .background(Color.accentColor, in: Circle())
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Advanced filters: filter by Script Extender requirement, warnings, or metadata source")
                .popover(isPresented: $showFilterPopover) {
                    advancedFilterPopover
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Advanced Filter Popover

    private var advancedFilterPopover: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Advanced Filters")
                    .font(.headline)
                Spacer()
                if isAdvancedFilterActive {
                    Button("Clear All") {
                        filterSERequired = .all
                        filterHasWarnings = .all
                        filterMetadataSources.removeAll()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Reset all advanced filters")
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Script Extender")
                    .font(.subheadline.bold())
                Picker("SE Filter", selection: $filterSERequired) {
                    ForEach(SEFilterOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .help("Filter mods by whether they require Script Extender")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Warnings")
                    .font(.subheadline.bold())
                Picker("Warning Filter", selection: $filterHasWarnings) {
                    ForEach(WarningFilterOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .help("Filter mods by whether they have validation warnings")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Metadata Source")
                    .font(.subheadline.bold())
                ForEach(allMetadataSources, id: \.self) { source in
                    Toggle(isOn: Binding(
                        get: { filterMetadataSources.contains(source) },
                        set: { isOn in
                            if isOn { filterMetadataSources.insert(source) }
                            else { filterMetadataSources.remove(source) }
                        }
                    )) {
                        Text(metadataSourceDisplayName(source))
                            .font(.caption)
                    }
                    .toggleStyle(.checkbox)
                    .help("Show only mods discovered via \(metadataSourceDisplayName(source).lowercased())")
                }
            }
        }
        .padding()
        .frame(width: 260)
    }

    /// All metadata source raw values for the filter popover.
    private var allMetadataSources: [String] {
        ["metaLsx", "infoJson", "filename", "modSettings"]
    }

    private func metadataSourceDisplayName(_ source: String) -> String {
        switch source {
        case "metaLsx": return "meta.lsx"
        case "infoJson": return "info.json"
        case "filename": return "Filename"
        case "modSettings": return "modsettings.lsx"
        default: return source
        }
    }

    // MARK: - Filtering

    private var filteredActiveMods: [ModInfo] {
        appState.activeMods.filter { matchesFilters($0) }
    }

    private var filteredInactiveMods: [ModInfo] {
        let filtered = appState.inactiveMods.filter { matchesFilters($0) }
        return sortInactiveMods(filtered)
    }

    private func sortInactiveMods(_ mods: [ModInfo]) -> [ModInfo] {
        let ascending = inactiveSortAscending
        return mods.sorted { a, b in
            let result: ComparisonResult
            switch currentSortOption {
            case .name:
                result = a.name.localizedCaseInsensitiveCompare(b.name)
            case .author:
                let cmp = a.author.localizedCaseInsensitiveCompare(b.author)
                result = cmp == .orderedSame ? a.name.localizedCaseInsensitiveCompare(b.name) : cmp
            case .category:
                let catA = a.category?.rawValue ?? 99
                let catB = b.category?.rawValue ?? 99
                if catA != catB {
                    result = catA < catB ? .orderedAscending : .orderedDescending
                } else {
                    result = a.name.localizedCaseInsensitiveCompare(b.name)
                }
            case .fileDate:
                let dateA = fileDate(for: a)
                let dateB = fileDate(for: b)
                if dateA == dateB {
                    result = a.name.localizedCaseInsensitiveCompare(b.name)
                } else {
                    result = dateA < dateB ? .orderedAscending : .orderedDescending
                }
            case .fileSize:
                let sizeA = fileSize(for: a)
                let sizeB = fileSize(for: b)
                if sizeA == sizeB {
                    result = a.name.localizedCaseInsensitiveCompare(b.name)
                } else {
                    result = sizeA < sizeB ? .orderedAscending : .orderedDescending
                }
            }
            return ascending ? (result == .orderedAscending) : (result == .orderedDescending)
        }
    }

    private func fileDate(for mod: ModInfo) -> Date {
        guard let path = mod.pakFilePath,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let date = attrs[.modificationDate] as? Date else {
            return .distantPast
        }
        return date
    }

    private func fileSize(for mod: ModInfo) -> UInt64 {
        guard let path = mod.pakFilePath,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
              let size = attrs[.size] as? UInt64 else {
            return 0
        }
        return size
    }

    private func matchesFilters(_ mod: ModInfo) -> Bool {
        if mod.isBasicGameModule { return true }

        if !searchText.isEmpty && !matchesSearch(mod) {
            return false
        }

        if isCategoryFilterActive {
            if let category = mod.category {
                if !selectedCategories.isEmpty && !selectedCategories.contains(category) {
                    return false
                }
            } else {
                if !showUncategorized {
                    return false
                }
            }
        }

        // Advanced filters
        switch filterSERequired {
        case .all: break
        case .seOnly:
            if !mod.requiresScriptExtender { return false }
        case .nonSEOnly:
            if mod.requiresScriptExtender { return false }
        }

        switch filterHasWarnings {
        case .all: break
        case .withWarnings:
            if appState.warnings(for: mod).isEmpty { return false }
        case .withoutWarnings:
            if !appState.warnings(for: mod).isEmpty { return false }
        }

        if !filterMetadataSources.isEmpty {
            if !filterMetadataSources.contains(mod.metadataSource.rawValue) { return false }
        }

        return true
    }

    private func matchesSearch(_ mod: ModInfo) -> Bool {
        let query = searchText.lowercased()
        return mod.name.lowercased().contains(query)
            || mod.author.lowercased().contains(query)
            || mod.folder.lowercased().contains(query)
            || mod.tags.contains { $0.lowercased().contains(query) }
    }

    // MARK: - Helpers


    // MARK: - Drag Insert

    /// Handle items dropped into the active list at a specific position via .onInsert.
    private func handleActiveListInsert(at index: Int, providers: [NSItemProvider]) {
        for provider in providers {
            provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let uuid = object as? String else { return }
                DispatchQueue.main.async {
                    if let mod = appState.inactiveMods.first(where: { $0.uuid == uuid }) {
                        // When filters are active, positional insert is ambiguous — fall back to append
                        if isCategoryFilterActive || isAdvancedFilterActive || !searchText.isEmpty {
                            appState.activateMod(mod)
                        } else {
                            appState.activateModAtPosition(mod, at: index)
                        }
                    }
                }
            }
        }
    }
}
