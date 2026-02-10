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

                Divider()

                // Metadata
                metadataSection

                // Dependencies
                if !mod.dependencies.isEmpty {
                    Divider()
                    dependenciesSection
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
