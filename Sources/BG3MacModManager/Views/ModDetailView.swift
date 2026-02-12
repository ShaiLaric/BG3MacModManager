import SwiftUI

/// Detail panel showing full mod information.
struct ModDetailView: View {
    let mod: ModInfo
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                header

                // Category
                if !mod.isBasicGameModule {
                    categorySection
                }

                // Per-mod warnings
                let modWarnings = appState.warnings(for: mod)
                if !modWarnings.isEmpty {
                    Divider()
                    issuesSection(modWarnings)
                }

                Divider()

                // Metadata
                metadataSection

                // Dependencies
                if !mod.dependencies.isEmpty {
                    Divider()
                    dependenciesSection
                }

                // Conflicts
                if !mod.conflicts.isEmpty {
                    Divider()
                    conflictsSection
                }

                // Tags
                if !mod.tags.isEmpty {
                    Divider()
                    tagsSection
                }

                // File Info
                Divider()
                fileInfoSection

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
            Text("Dependencies")
                .font(.headline)

            let missing = appState.missingDependencies(for: mod)

            ForEach(mod.dependencies) { dep in
                HStack {
                    Image(systemName: missing.contains(where: { $0.uuid == dep.uuid }) ?
                          "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(missing.contains(where: { $0.uuid == dep.uuid }) ? .red : .green)

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

            if !missing.isEmpty {
                Text("Missing \(missing.count) required mod(s)")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
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
                        .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
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
                        .foregroundStyle(colorForSeverity(warning.severity))

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

    private func colorForSeverity(_ severity: ModWarning.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning:  return .yellow
        case .info:     return .blue
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
