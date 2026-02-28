// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Detail panel showing full mod information.
struct ModDetailView: View {
    let mod: ModInfo
    @EnvironmentObject var appState: AppState
    @State private var isEditingNexusURL = false
    @State private var editingNexusURL = ""
    @State private var isEditingNote = false
    @State private var editingNoteText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                header

                // Category
                if !mod.isBasicGameModule {
                    categorySection
                }

                // Nexus Mods link
                if !mod.isBasicGameModule {
                    nexusSection
                }

                // User notes
                if !mod.isBasicGameModule {
                    notesSection
                }

                // Per-mod warnings
                let modWarnings = appState.warnings(for: mod)
                if !modWarnings.isEmpty {
                    Divider()
                    issuesSection(modWarnings)
                }

                Divider()

                // Metadata
                DisclosureGroup("Metadata") {
                    metadataSection
                }

                // Dependencies
                if !mod.dependencies.isEmpty {
                    Divider()
                    DisclosureGroup("Dependencies") {
                        dependenciesSection
                    }
                }

                // Conflicts
                if !mod.conflicts.isEmpty {
                    Divider()
                    DisclosureGroup("Conflicts") {
                        conflictsSection
                    }
                }

                // Tags
                if !mod.tags.isEmpty {
                    Divider()
                    DisclosureGroup("Tags") {
                        tagsSection
                    }
                }

                // File Info
                Divider()
                DisclosureGroup("File Info") {
                    fileInfoSection
                }

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(mod.name)
                    .font(.title2.bold())

                if mod.requiresScriptExtender {
                    Text("Script Extender")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange, in: RoundedRectangle(cornerRadius: 4))
                        .help("This mod requires bg3se-macos (Script Extender) to function")
                }
            }

            if mod.author != "Unknown" {
                Text("by \(mod.author)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Version \(mod.version.description)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Category

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Load Order Category")
                .font(.headline)
                .help("Determines where this mod is placed when using Smart Sort. Based on the BG3 community's 5-tier load order convention.")

            HStack(spacing: 8) {
                if let category = mod.category {
                    Text(category.displayName)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(category.color, in: RoundedRectangle(cornerRadius: 4))
                        .help(category.tooltip)
                } else {
                    Text("Uncategorized")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("No category detected from tags, name, or known-mods database. This mod will be sorted into the middle of the load order (with Content mods). Use the picker to assign a tier manually.")
                }

                Spacer()

                Picker("", selection: categoryBinding) {
                    Text("Auto-detect").tag(nil as ModCategory?)
                    Divider()
                    ForEach(ModCategory.allCases, id: \.self) { cat in
                        Label(cat.displayName, systemImage: cat.icon)
                            .tag(cat as ModCategory?)
                    }
                }
                .frame(width: 150)
                .help("Manually set this mod's load order tier, overriding auto-detection. Choose \"Auto-detect\" to clear the override and let the app infer the category from tags and mod name.")
            }

            if appState.categoryService.override(for: mod.uuid) != nil {
                Text("User override active")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("You have manually set this mod's category. It will not be auto-detected. Choose \"Auto-detect\" in the picker to remove this override.")
            }
        }
    }

    private var categoryBinding: Binding<ModCategory?> {
        Binding(
            get: { appState.categoryService.override(for: mod.uuid) },
            set: { appState.setCategoryOverride($0, for: mod) }
        )
    }

    // MARK: - Nexus Mods

    private var nexusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nexus Mods")
                .font(.headline)

            HStack(spacing: 8) {
                let currentURL = appState.nexusURLService.url(for: mod.uuid)

                if let urlString = currentURL, !urlString.isEmpty {
                    Text(urlString)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        if let url = URL(string: urlString) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Image(systemName: "safari")
                    }
                    .buttonStyle(.plain)
                    .help("Open in browser")

                    Button {
                        editingNexusURL = urlString
                        isEditingNexusURL = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .help("Edit URL")

                    Button {
                        appState.setNexusURL(nil, for: mod)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help("Remove URL")
                } else {
                    Text("No URL set")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Set URL") {
                        editingNexusURL = ""
                        isEditingNexusURL = true
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            if isEditingNexusURL {
                HStack {
                    TextField("https://www.nexusmods.com/baldursgate3/mods/...", text: $editingNexusURL)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .onSubmit { saveNexusURL() }

                    Button("Save") { saveNexusURL() }
                        .font(.caption)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)

                    Button("Cancel") { isEditingNexusURL = false }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }

            // Update status
            if let updateInfo = appState.nexusUpdateInfo(for: mod) {
                HStack(spacing: 8) {
                    if updateInfo.hasUpdate {
                        Image(systemName: "arrow.up.circle.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Update Available: \(updateInfo.latestVersion)")
                                .font(.caption.bold())
                                .foregroundStyle(.yellow)
                            Text("Installed: \(updateInfo.installedVersion)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("View on Nexus") {
                            if let url = URL(string: updateInfo.nexusURL) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Open this mod's Nexus page to download the update")
                    } else {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("Up to date")
                            .font(.caption)
                            .foregroundStyle(.green)
                        Spacer()
                    }
                }

                Text("Last checked: \(updateInfo.checkedDate, style: .relative) ago")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func saveNexusURL() {
        appState.setNexusURL(editingNexusURL.isEmpty ? nil : editingNexusURL, for: mod)
        isEditingNexusURL = false
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)

            let currentNote = appState.modNotesService.note(for: mod.uuid)

            if isEditingNote {
                TextEditor(text: $editingNoteText)
                    .font(.body)
                    .frame(minHeight: 60, maxHeight: 150)
                    .border(Color.borderMuted, width: 1)

                HStack {
                    Spacer()

                    Button("Cancel") {
                        isEditingNote = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Discard changes to note")

                    Button("Save") {
                        appState.setModNote(
                            editingNoteText.isEmpty ? nil : editingNoteText,
                            for: mod
                        )
                        isEditingNote = false
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("Save note for this mod")
                }
            } else if let note = currentNote {
                Text(note)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack {
                    Spacer()

                    Button {
                        editingNoteText = note
                        isEditingNote = true
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .help("Edit note")

                    Button {
                        appState.setModNote(nil, for: mod)
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help("Remove note")
                }
            } else {
                Button("Add Note") {
                    editingNoteText = ""
                    isEditingNote = true
                }
                .font(.caption)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Add a personal note for this mod")
            }
        }
    }

    // MARK: - Metadata

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !mod.modDescription.isEmpty {
                Text(mod.modDescription)
                    .font(.body)
            }

            detailRow("UUID", mod.uuid, monospaced: true, copyable: true)
            detailRow("Folder", mod.folder, copyable: true)
            detailRow("Version64", String(mod.version64), monospaced: true)
            detailRow("Source", mod.metadataSource.rawValue)
        }
    }

    // MARK: - Dependencies

    private var dependenciesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Dependencies")
                    .font(.headline)
                    .help("Mods that must be active and loaded before this mod for it to work correctly")

                Spacer()

                let missing = appState.missingDependencies(for: mod)
                let activatable = missing.filter { dep in
                    appState.inactiveMods.contains(where: { $0.uuid == dep.uuid })
                }
                if !activatable.isEmpty {
                    Button("Activate Missing") {
                        let count = appState.activateMissingDependencies(for: mod)
                        appState.statusMessage = "Activated \(count) missing dependency(ies)"
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Activate \(activatable.count) missing dependency(ies) from the inactive mod list")
                }
            }

            directDependenciesList

            // Transitive dependency tree (shown when there are nested deps)
            let transitive = appState.transitiveDependencies(for: mod)
            if transitive.contains(where: { $0.depth > 0 }) {
                transitiveDependencyTree(transitive)
            }
        }
    }

    private var directDependenciesList: some View {
        let missing = appState.missingDependencies(for: mod)

        return ForEach(mod.dependencies) { dep in
            HStack {
                let isMissing = missing.contains(where: { $0.uuid == dep.uuid })
                Image(systemName: isMissing ?
                      "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(isMissing ? .red : .green)
                    .help(isMissing ? "This dependency is missing or inactive" : "This dependency is satisfied")

                VStack(alignment: .leading) {
                    Text(dep.name.isEmpty ? dep.uuid : dep.name)
                        .font(.body)
                    if !dep.folder.isEmpty {
                        Text(dep.folder)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func transitiveDependencyTree(
        _ deps: [(depth: Int, dependency: ModDependency, resolved: ModInfo?)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Dependency Tree")
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
                .padding(.top, 4)
                .help("Full transitive dependency chain — shows nested dependencies required by this mod's direct dependencies")

            ForEach(Array(deps.enumerated()), id: \.offset) { _, entry in
                let activeUUIDs = Set(appState.activeMods.map(\.uuid))
                let isActive = activeUUIDs.contains(entry.dependency.uuid)
                let name = entry.dependency.name.isEmpty ? entry.dependency.uuid : entry.dependency.name
                HStack(spacing: 4) {
                    // Indentation based on depth
                    if entry.depth > 0 {
                        Text(String(repeating: "  ", count: entry.depth))
                            .font(.caption.monospaced())
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Image(systemName: isActive ? "checkmark.circle.fill" : "xmark.circle")
                        .font(.caption2)
                        .foregroundStyle(isActive ? .green : .red)

                    Text(name)
                        .font(.caption)
                        .lineLimit(1)

                    if entry.resolved == nil {
                        Text("(not installed)")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .help(isActive
                    ? "\(name) is active at position \(activePosition(for: entry.dependency.uuid))"
                    : "\(name) is not in the active load order")
            }
        }
    }

    private func activePosition(for uuid: String) -> String {
        if let index = appState.activeMods.firstIndex(where: { $0.uuid == uuid }) {
            return "#\(index + 1)"
        }
        return "N/A"
    }

    // MARK: - Conflicts

    private var conflictsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Declared Conflicts")
                .font(.headline)
                .help("Conflicts declared by this mod in its meta.lsx metadata. If a conflicting mod is also active, it may cause issues in-game.")

            let activeUUIDs = Set(appState.activeMods.map(\.uuid))

            ForEach(mod.conflicts) { conflict in
                let isActive = activeUUIDs.contains(conflict.uuid)
                HStack {
                    Image(systemName: isActive ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isActive ? .yellow : .green)
                        .help(isActive
                            ? "This conflicting mod is currently active — having both enabled may cause issues"
                            : "This conflicting mod is not active — no conflict at this time")

                    VStack(alignment: .leading) {
                        Text(conflict.name.isEmpty ? conflict.uuid : conflict.name)
                            .font(.body)
                        if !conflict.folder.isEmpty {
                            Text(conflict.folder)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if isActive {
                        Text("Active")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.yellow, in: RoundedRectangle(cornerRadius: 3))
                            .help("This mod is in your active load order and conflicts with \(mod.name). Consider deactivating one of them.")
                    }
                }
            }

            let activeConflictCount = mod.conflicts.filter { activeUUIDs.contains($0.uuid) }.count
            if activeConflictCount > 0 {
                Text("\(activeConflictCount) active conflict\(activeConflictCount == 1 ? "" : "s") detected")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .help("Deactivate one of the conflicting mods, or check their mod pages for compatibility patches.")
            }
        }
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tags")
                .font(.headline)

            FlowLayout(spacing: 6) {
                ForEach(mod.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.bgTag, in: RoundedRectangle(cornerRadius: 4))
                }
            }
        }
    }

    // MARK: - File Info

    private var fileInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("File Info")
                .font(.headline)

            if let fileName = mod.pakFileName {
                detailRow("File", fileName, copyable: true)
            }
            if let filePath = mod.pakFilePath {
                HStack {
                    Text("Path")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .trailing)
                    Text(filePath.path)
                        .font(.caption.monospaced())
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Spacer()
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([filePath])
                    } label: {
                        Image(systemName: "arrow.right.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                }

                // Delete button for inactive mods only
                if !mod.isBasicGameModule && !appState.activeMods.contains(where: { $0.uuid == mod.uuid }) {
                    Button(role: .destructive) {
                        appState.requestDeleteMod(mod)
                    } label: {
                        Label("Delete from Disk...", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Permanently remove this mod's PAK file from the Mods folder. This cannot be undone.")
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Issues

    private func issuesSection(_ warnings: [ModWarning]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Issues")
                .font(.headline)

            ForEach(warnings) { warning in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: warning.severity.icon)
                        .foregroundStyle(warning.severity.color)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(warning.message)
                            .font(.body)
                        if !warning.detail.isEmpty {
                            Text(warning.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }


    // MARK: - Helpers

    private func detailRow(_ label: String, _ value: String, monospaced: Bool = false, copyable: Bool = false) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)
            if monospaced {
                Text(value)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            Spacer()
            if copyable {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(value, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")
            }
        }
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                                  proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}
