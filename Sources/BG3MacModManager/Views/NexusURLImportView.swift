// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

/// View for bulk-importing Nexus URLs from CSV, TSV, JSON, or plain text files.
struct NexusURLImportView: View {
    @EnvironmentObject var appState: AppState

    @State private var importResult: NexusURLImportService.ImportResult?
    @State private var errorText: String?
    @State private var isApplied = false
    @State private var selectedFileName: String?

    private let importService = NexusURLImportService()

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Text("Bulk Nexus URL Import")
                    .font(.headline)
                Spacer()
                if let fileName = selectedFileName {
                    Text(fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Button("Select File...") {
                    selectFile()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .help("Choose a CSV, TSV, JSON, or TXT file with mod names and Nexus URLs")
            }
            .padding()

            Divider()

            if let result = importResult {
                resultView(result)
            } else if let error = errorText {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                emptyStateView
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "link.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Import Nexus Mods URLs in Bulk")
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Supported formats:")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Group {
                    Label("CSV/TSV — Two columns: mod name, Nexus URL", systemImage: "tablecells")
                    Label("JSON — Array of objects or UUID-to-URL dictionary", systemImage: "curlybraces")
                    Label("TXT — One Nexus URL per line", systemImage: "doc.plaintext")
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 400)

            Spacer()
        }
    }

    // MARK: - Result View

    private func resultView(_ result: NexusURLImportService.ImportResult) -> some View {
        VStack(spacing: 0) {
            // Stats bar
            HStack(spacing: 16) {
                statBox("Parsed", count: result.totalParsed, color: .secondary)
                statBox("Matched", count: result.matched.count, color: .green)
                statBox("Unmatched", count: result.unmatched.count,
                         color: result.unmatched.isEmpty ? .secondary : .orange)
                Spacer()
                if !isApplied && !result.matched.isEmpty {
                    Button("Apply \(result.matched.count) URL(s)") {
                        applyMatches(result)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .help("Set Nexus URLs for all matched mods")
                } else if isApplied {
                    Label("Applied", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }
            .padding()

            Divider()

            // Matched entries
            List {
                if !result.matched.isEmpty {
                    Section("Matched Mods (\(result.matched.count))") {
                        ForEach(result.matched) { entry in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.matchedMod.name)
                                        .font(.body)
                                    Text(entry.parsedEntry.nexusURL)
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                                Spacer()
                                Text(entry.matchType.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 3))
                            }
                        }
                    }
                }

                if !result.unmatched.isEmpty {
                    Section("Unmatched Entries (\(result.unmatched.count))") {
                        ForEach(Array(result.unmatched.enumerated()), id: \.offset) { _, entry in
                            VStack(alignment: .leading, spacing: 2) {
                                if !entry.identifier.isEmpty {
                                    Text(entry.identifier)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                                Text(entry.nexusURL)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func statBox(_ label: String, count: Int, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Actions

    private func selectFile() {
        let panel = NSOpenPanel()
        panel.title = "Select Nexus URL Import File"
        panel.allowedContentTypes = [
            UTType.commaSeparatedText,
            UTType.tabSeparatedText,
            UTType.json,
            UTType.plainText
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        selectedFileName = url.lastPathComponent
        importResult = nil
        errorText = nil
        isApplied = false

        do {
            let allMods = appState.activeMods + appState.inactiveMods
            importResult = try importService.parseAndMatch(
                fileURL: url,
                installedMods: allMods
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func applyMatches(_ result: NexusURLImportService.ImportResult) {
        var urls: [String: String] = [:]
        for entry in result.matched {
            urls[entry.matchedMod.uuid] = entry.parsedEntry.nexusURL
        }
        appState.bulkSetNexusURLs(urls)
        isApplied = true
    }
}
