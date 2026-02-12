import SwiftUI

/// Main mod management view with active (load order) and inactive mod lists.
struct ModListView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var draggedMod: ModInfo?
    @State private var warningsExpanded = false

    var body: some View {
        HSplitView {
            // Left: Active + Inactive mod lists
            VStack(spacing: 0) {
                // Warnings banner
                if !appState.warnings.isEmpty {
                    warningsBanner
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

            List(selection: $appState.selectedModID) {
                ForEach(filteredActiveMods) { mod in
                    ModRowView(mod: mod, isActive: true)
                        .tag(mod.uuid)
                        .contextMenu {
                            if !mod.isBasicGameModule {
                                Button("Deactivate") { appState.deactivateMod(mod) }
                            }
                            Divider()
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

            List(selection: $appState.selectedModID) {
                ForEach(filteredInactiveMods) { mod in
                    ModRowView(mod: mod, isActive: false)
                        .tag(mod.uuid)
                        .contextMenu {
                            Button("Activate") { appState.activateMod(mod) }
                            Divider()
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
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    // MARK: - Detail Panel

    @ViewBuilder
    private var modDetailPanel: some View {
        if let mod = appState.selectedMod {
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
