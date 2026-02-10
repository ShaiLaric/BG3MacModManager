import SwiftUI

/// Main mod management view with active (load order) and inactive mod lists.
struct ModListView: View {
    @EnvironmentObject var appState: AppState
    @State private var searchText = ""
    @State private var draggedMod: ModInfo?

    var body: some View {
        HSplitView {
            // Left: Active + Inactive mod lists
            VStack(spacing: 0) {
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

    // MARK: - Active Mods

    private var activeModsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Active Mods (\(appState.activeMods.count))", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                Spacer()
                Menu {
                    Button("Activate All") { appState.activateAll() }
                    Button("Deactivate All") { appState.deactivateAll() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
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
}
