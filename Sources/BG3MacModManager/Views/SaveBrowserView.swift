// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct SaveBrowserView: View {
    @EnvironmentObject private var appState: AppState

    private var campaigns: [(name: String, saves: [SaveGameSummary])] {
        Dictionary(grouping: appState.saveGames, by: \.campaignName)
            .map { ($0.key, $0.value.sorted { $0.modifiedAt > $1.modifiedAt }) }
            .sorted { lhs, rhs in
                (lhs.saves.first?.modifiedAt ?? .distantPast) > (rhs.saves.first?.modifiedAt ?? .distantPast)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if appState.saveGames.isEmpty && !appState.isScanningSaveGames {
                emptyState
            } else {
                HSplitView {
                    saveList
                        .frame(minWidth: 300, idealWidth: 370)
                    selectedSaveDetail
                        .frame(minWidth: 390)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Save Games")
                    .font(.title2.bold())
                Text("Link a campaign or individual save to a mod profile; associations never switch profiles automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if appState.isScanningSaveGames {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await appState.refreshSaveGames() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isScanningSaveGames)
        }
        .padding()
    }

    private var saveList: some View {
        List(selection: $appState.selectedSaveID) {
            ForEach(campaigns, id: \.name) { campaign in
                Section {
                    ForEach(campaign.saves) { save in
                        saveRow(save)
                            .tag(save.id)
                    }
                } header: {
                    HStack {
                        Text(campaign.name)
                        Spacer()
                        if let newest = campaign.saves.first,
                           let resolved = appState.resolvedAssociation(for: newest),
                           resolved.matchedKind == .campaign {
                            Text(profileName(for: resolved.association.profileID))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if let newest = campaign.saves.first {
                            associationMenu(for: newest, kind: .campaign, compact: true)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func saveRow(_ save: SaveGameSummary) -> some View {
        HStack(spacing: 9) {
            Image(systemName: save.isReadable ? "doc.circle" : "exclamationmark.triangle.fill")
                .foregroundStyle(save.isReadable ? Color.secondary : Color.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(save.displayName)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(save.modifiedAt, style: .relative)
                    Text("•")
                    Text("\(save.mods.count) mods")
                    if let resolved = appState.resolvedAssociation(for: save) {
                        Text("•")
                        Text(resolved.matchedKind == .save ? "save override" : "campaign")
                            .foregroundStyle(.blue)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var selectedSaveDetail: some View {
        if let save = appState.selectedSave {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(save.displayName)
                                .font(.title3.bold())
                            Text(save.campaignName)
                                .foregroundStyle(.secondary)
                            Text(save.modifiedAt.formatted(date: .abbreviated, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Import Order") {
                            Task { await appState.importFromSaveFile(url: save.fileURL) }
                        }
                        .disabled(!save.isReadable)
                    }

                    associationSection(save)

                    if let error = save.readError {
                        Label("Could not inspect this save", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    } else {
                        comparisonSection(save)
                        modListSection(save)
                    }

                    Text(save.relativePath)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                }
                .padding()
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("Select a save to inspect its mod order")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func associationSection(_ save: SaveGameSummary) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Profile Association")
                .font(.headline)
            if let resolved = appState.resolvedAssociation(for: save) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profileName(for: resolved.association.profileID))
                            .fontWeight(.medium)
                        Text(resolved.matchedKind == .save
                             ? "Individual-save override (takes precedence over campaign)"
                             : "Campaign association")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Prepare to Play") {
                        Task { await appState.prepareToPlay(save) }
                    }
                    .buttonStyle(.borderedProminent)
                    Menu("Change") {
                        profileButtons(for: save, kind: resolved.matchedKind)
                        Divider()
                        Button("Remove Association", role: .destructive) {
                            appState.removeAssociation(resolved.association)
                        }
                    }
                }
            } else {
                HStack {
                    Text("No profile is associated with this save or campaign.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    associationMenu(for: save, kind: .campaign, compact: false)
                    associationMenu(for: save, kind: .save, compact: false)
                }
            }

            if appState.resolvedAssociation(for: save)?.matchedKind == .campaign {
                associationMenu(for: save, kind: .save, compact: false, title: "Add Save Override")
            }
        }
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func comparisonSection(_ save: SaveGameSummary) -> some View {
        if let comparison = appState.saveProfileComparison(for: save) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Comparison")
                    .font(.headline)
                Label(
                    comparison.summary,
                    systemImage: comparison.hasCurrentMismatch ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
                )
                .foregroundStyle(comparison.hasCurrentMismatch ? Color.orange : Color.green)
                if comparison.saveOrderDiffersFromProfile {
                    Text("The save itself recorded a different order than the associated profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func modListSection(_ save: SaveGameSummary) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Recorded Mod Order (\(save.mods.count))")
                .font(.headline)
            ForEach(Array(save.mods.enumerated()), id: \.element.id) { index, mod in
                HStack(alignment: .firstTextBaseline) {
                    Text("\(index + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                    Text(mod.name)
                    Spacer()
                    Text(Version64(rawValue: mod.version64).description)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "externaldrive.badge.questionmark")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No BG3 saves found")
                .font(.headline)
            Text(FileLocations.savegamesFolder.path)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer()
        }
    }

    private func profileName(for id: UUID) -> String {
        appState.profiles.first(where: { $0.id == id })?.name ?? "Missing profile"
    }

    private func associationMenu(
        for save: SaveGameSummary,
        kind: SaveProfileAssociation.TargetKind,
        compact: Bool,
        title: String? = nil
    ) -> some View {
        Menu {
            profileButtons(for: save, kind: kind)
        } label: {
            if compact {
                Image(systemName: "link.badge.plus")
            } else {
                Text(title ?? (kind == .campaign ? "Associate Campaign" : "Associate Save"))
            }
        }
        .disabled(appState.profiles.isEmpty)
        .help(appState.profiles.isEmpty ? "Create a mod profile first" : "Choose the profile this target should use")
    }

    @ViewBuilder
    private func profileButtons(
        for save: SaveGameSummary,
        kind: SaveProfileAssociation.TargetKind
    ) -> some View {
        if appState.profiles.isEmpty {
            Text("No profiles available")
        } else {
            ForEach(appState.profiles) { profile in
                Button(profile.name) {
                    appState.associate(save, kind: kind, with: profile)
                }
            }
        }
    }
}
