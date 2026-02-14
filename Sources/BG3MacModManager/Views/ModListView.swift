import SwiftUI

/// Main mod management view with active (load order) and inactive mod lists.
struct ModListView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var warningsExpanded = false
    @State private var activeDropTargeted = false

    var body: some View {
        HSplitView {
            // Left: Active + Inactive mod lists
            VStack(spacing: 0) {
                // Primary action bar
                actionBar
                Divider()

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
                            .fill(Color.white.opacity(0.9))
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

            Spacer()

            Button {
                appState.launchGame()
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
        .background(Color.accentColor.opacity(0.08))
    }

    // MARK: - Warnings Banner

    private var warningsBanner: some View {
        let criticalCount = appState.warnings.filter { $0.severity == .critical }.count
        let warningCount = appState.warnings.filter { $0.severity == .warning }.count

        return VStack(spacing: 0) {
            // Summary bar (always visible when warnings exist)
            Button {
                withAnimation { warningsExpanded.toggle() }
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
                .background(criticalCount > 0 ? Color.red.opacity(0.1) : Color.yellow.opacity(0.1))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(appState.warnings) { warning in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: warning.severity.icon)
                            .foregroundStyle(colorForSeverity(warning.severity))

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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxHeight: 150)
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
                        .moveDisabled(!searchText.isEmpty)
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
                            if mod.pakFilePath != nil {
                                Divider()
                                Button("Extract to Folder...") {
                                    appState.extractMod(mod)
                                }
                            }
                        }
                }
                .onMove { source, destination in
                    appState.moveActiveMod(from: source, to: destination)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .dropDestination(for: String.self) { uuids, _ in
                var activated = 0
                for uuid in uuids {
                    if let mod = appState.inactiveMods.first(where: { $0.uuid == uuid }) {
                        appState.activateMod(mod)
                        activated += 1
                    }
                }
                return activated > 0
            } isTargeted: { targeted in
                activeDropTargeted = targeted
            }
            .overlay {
                if activeDropTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.green, lineWidth: 2)
                        .padding(2)
                        .allowsHitTesting(false)
                }
            }
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
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List(selection: $appState.selectedModIDs) {
                ForEach(filteredInactiveMods) { mod in
                    ModRowView(mod: mod, isActive: false)
                        .tag(mod.uuid)
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
                            if mod.pakFilePath != nil {
                                Divider()
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

    // MARK: - Filtering

    private var filteredActiveMods: [ModInfo] {
        guard !searchText.isEmpty else { return appState.activeMods }
        return appState.activeMods.filter { matchesSearch($0) }
    }

    private var filteredInactiveMods: [ModInfo] {
        guard !searchText.isEmpty else { return appState.inactiveMods }
        return appState.inactiveMods.filter { matchesSearch($0) }
    }

    private func matchesSearch(_ mod: ModInfo) -> Bool {
        let query = searchText.lowercased()
        return mod.name.lowercased().contains(query)
            || mod.author.lowercased().contains(query)
            || mod.folder.lowercased().contains(query)
            || mod.tags.contains { $0.lowercased().contains(query) }
    }

    // MARK: - Helpers

    private func colorForSeverity(_ severity: ModWarning.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning:  return .yellow
        case .info:     return .blue
        }
    }
}
