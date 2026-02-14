// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Sheet for resolving duplicate UUID conflicts by choosing which PAK files to keep.
struct DuplicateResolverView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Text("Duplicate Mods Detected")
                .font(.headline)

            Text("The following mods share the same UUID. Only one copy of each should be kept to prevent the game from resetting your load order.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 450)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(appState.duplicateGroups.indices, id: \.self) { groupIndex in
                        duplicateGroupSection(appState.duplicateGroups[groupIndex])
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 400)

            HStack {
                Spacer()
                Button("Done") {
                    appState.showDuplicateResolver = false
                }
                .keyboardShortcut(.defaultAction)
                .help("Close the duplicate resolver")
            }
        }
        .padding(24)
        .frame(minWidth: 500)
    }

    private func duplicateGroupSection(_ mods: [ModInfo]) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(mods.first?.name ?? "Unknown")
                        .font(.headline)
                    Text("(\(mods.count) copies)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("UUID: \(mods.first?.uuid ?? "")")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                ForEach(mods, id: \.pakFileName) { mod in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mod.pakFileName ?? "Unknown file")
                                .font(.body)

                            if let pakURL = mod.pakFilePath {
                                fileInfoRow(pakURL)
                            }

                            Text("Source: \(mod.metadataSource.rawValue)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        Button(role: .destructive) {
                            Task { await appState.deletePakFile(for: mod) }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(mod.pakFilePath == nil)
                        .help("Delete this PAK file from disk")
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(4)
        }
    }

    private func fileInfoRow(_ url: URL) -> some View {
        HStack(spacing: 12) {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                if let size = attrs[.size] as? Int64 {
                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let date = attrs[.modificationDate] as? Date {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
