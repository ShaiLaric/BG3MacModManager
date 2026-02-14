// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import AppKit

/// Summary dialog shown after importing a load order with missing mods.
struct ImportSummaryView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Import Summary")
                .font(.title2.bold())

            if let summary = appState.importSummaryResult {
                // Stats row
                HStack(spacing: 16) {
                    statBox(label: "In File", value: "\(summary.totalInFile)")
                    statBox(label: "Matched", value: "\(summary.matchedCount)")
                    statBox(label: "Missing", value: "\(summary.missingMods.count)")
                }

                if summary.matchedCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(summary.matchedCount) mod(s) activated in the imported order.")
                            .font(.body)
                    }
                }

                if !summary.missingMods.isEmpty {
                    Divider()

                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("The following mods were not found locally:")
                            .font(.headline)
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(summary.missingMods) { mod in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(mod.name)
                                            .font(.body.bold())
                                        Text(mod.uuid)
                                            .font(.caption.monospaced())
                                            .foregroundStyle(.secondary)
                                            .textSelection(.enabled)
                                    }

                                    Spacer()

                                    if let urlString = mod.nexusURL,
                                       let url = URL(string: urlString) {
                                        Button {
                                            NSWorkspace.shared.open(url)
                                        } label: {
                                            Label("Nexus", systemImage: "safari")
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                        .help("Open mod page on Nexus Mods")
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .frame(maxHeight: 300)

                    HStack {
                        Spacer()
                        Button("Copy Missing Mod Names") {
                            let names = summary.missingMods.map(\.name).joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(names, forType: .string)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    appState.showImportSummary = false
                    appState.importSummaryResult = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 500, minHeight: 300, maxHeight: 600)
    }

    private func statBox(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}
