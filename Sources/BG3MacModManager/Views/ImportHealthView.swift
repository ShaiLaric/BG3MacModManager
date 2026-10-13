// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Review installed files and likely activation issues before changing the load order.
struct ImportHealthView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xl) {
            Text("Import Health Report").font(.title2.bold())
            Text("Files are installed. Review these findings before activating new mods; your load order is saved only when you choose Save.")
                .foregroundStyle(.secondary)

            if let report = appState.importHealthReport {
                HStack(spacing: Spacing.xl) {
                    stat("Imported", report.importedMods.count)
                    stat("New", report.activationCandidates.count)
                    stat("Replaced", report.replacedFileCount)
                    stat("Critical", report.criticalCount)
                    stat("Warnings", report.warningCount)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        if !report.importErrors.isEmpty {
                            GroupBox("Some files could not be imported") {
                                VStack(alignment: .leading, spacing: Spacing.md) {
                                    ForEach(Array(report.importErrors.enumerated()), id: \.offset) { _, message in
                                        Label(message, systemImage: "exclamationmark.triangle.fill")
                                            .foregroundStyle(ModWarning.Severity.warning.color)
                                            .textSelection(.enabled)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }

                        GroupBox("Imported Mods") {
                            VStack(alignment: .leading, spacing: Spacing.md) {
                                ForEach(Array(report.importedMods.enumerated()), id: \.offset) { _, mod in
                                    HStack {
                                        VStack(alignment: .leading, spacing: Spacing.xs) {
                                            Text(mod.name).font(.body.bold())
                                            Text(mod.pakFileName ?? mod.uuid)
                                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        Text(mod.version.description).font(.caption.monospaced())
                                    }
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if report.findings.isEmpty {
                            Label("No issues found in the import checks", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("Checks preview using the imported mods with your current active order.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(report.findings) { finding in
                                HStack(alignment: .top, spacing: Spacing.md) {
                                    Image(systemName: finding.severity.icon)
                                        .foregroundStyle(finding.severity.color)
                                    VStack(alignment: .leading, spacing: Spacing.xs) {
                                        Text(finding.message).font(.body.bold())
                                        if !finding.detail.isEmpty {
                                            Text(finding.detail).font(.caption).foregroundStyle(.secondary)
                                        }
                                        if let advice = advice(for: finding.suggestedAction) {
                                            Text(advice).font(.caption)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(Spacing.lg)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(finding.severity.backgroundColor, in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }

                HStack {
                    if report.findings.contains(where: { $0.category == .duplicateUUID }) {
                        Button("Review Duplicates") {
                            appState.finishImportHealthReview(activate: false, followup: "duplicates")
                        }
                        .help("Keep new mods inactive and choose which duplicate files to keep")
                    }
                    if report.findings.contains(where: { $0.category == .seRequired }) {
                        Button("View Script Extender") {
                            appState.finishImportHealthReview(activate: false, followup: "scriptExtender")
                        }
                        .help("Keep new mods inactive and inspect Script Extender deployment")
                    }
                    Spacer()
                }
                HStack {
                    Spacer()
                    Button(report.activationCandidates.isEmpty ? "Done" : "Keep New Mods Inactive", role: .cancel) {
                        appState.finishImportHealthReview(activate: false)
                    }
                    .keyboardShortcut(.cancelAction)
                    .help("Close this report; installed files are kept and new mods stay inactive")
                    if !report.activationCandidates.isEmpty {
                        Button("Activate New Mods") { appState.finishImportHealthReview(activate: true) }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                            .help("Add the new mods to the active load order as one undoable action")
                    }
                }
            }
        }
        .padding(Spacing.xxl)
        .frame(width: 680, height: 620)
        .interactiveDismissDisabled()
    }

    private func stat(_ label: String, _ count: Int) -> some View {
        VStack(spacing: Spacing.xs) {
            Text("\(count)").font(.title2.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(Spacing.md)
        .background(Color.statBoxBg, in: RoundedRectangle(cornerRadius: 6))
    }

    private func advice(for action: ModWarning.SuggestedAction?) -> String? {
        switch action {
        case .autoSort: return "After activation, use Smart Sort to check dependency order and load-order rules."
        case .installDependency: return "Install the required dependency before using this mod."
        case .activateDependencies: return "Activate the installed dependency before activating this mod."
        case .installScriptExtender, .viewSEStatus: return "Check Script Extender deployment before launching the game."
        case .deactivateMod: return "Review the involved mods and keep a compatible configuration."
        default: return nil
        }
    }
}
