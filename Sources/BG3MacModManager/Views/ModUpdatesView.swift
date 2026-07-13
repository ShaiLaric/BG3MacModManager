// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct ModUpdatesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var restoreCandidate: ModUpdateHistoryRecord?

    private var updateResults: [NexusUpdateResult] {
        appState.nexusUpdateResults.values
            .filter { $0.hasUpdate || $0.versionDiffers }
            .sorted { $0.latestName.localizedCaseInsensitiveCompare($1.latestName) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    acquisitionStatus
                    nexusResultsSection
                    historySection
                }
                .padding()
            }
        }
        .confirmationDialog(
            "Restore Previous Version?",
            isPresented: Binding(
                get: { restoreCandidate != nil },
                set: { if !$0 { restoreCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Restore", role: .destructive) {
                if let record = restoreCandidate {
                    Task { await appState.restorePreviousModVersion(record) }
                }
                restoreCandidate = nil
            }
            Button("Cancel", role: .cancel) { restoreCandidate = nil }
        } message: {
            if let record = restoreCandidate {
                Text("This replaces the installed PAK for \(record.modName) with the durable backup from before the update.")
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Mod Updates")
                    .font(.title2.bold())
                Text("Inspect, back up, install, verify, and roll back mod updates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if appState.isUpdatingMod {
                ProgressView()
                    .controlSize(.small)
                Text(appState.modUpdateProgress.stage.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                Task { await appState.checkForNexusUpdates() }
            } label: {
                Label("Check Nexus", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(appState.isCheckingForUpdates || appState.nexusAPIService.apiKey == nil)
        }
        .padding()
    }

    private var acquisitionStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Acquisition")
                .font(.headline)
            Label("Browser download + manual archive selection is available", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Label("Direct Nexus download is capability-gated", systemImage: "lock.circle")
                .foregroundStyle(.secondary)
            Text(ModUpdateAcquisitionCapability.current.directDownloadReason)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
    }

    private var nexusResultsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Available or Different Versions (\(updateResults.count))")
                .font(.headline)
            if updateResults.isEmpty {
                Text("No differing Nexus versions are in the current cache. You can still update any installed mod from its detail view.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(updateResults) { result in
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(result.latestName)
                                .fontWeight(.medium)
                            Text("Installed \(result.installedVersion) • Nexus \(result.latestVersion)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let mod = installedMod(uuid: result.modUUID) {
                            Button("Download in Browser") { appState.openNexusPage(for: mod) }
                            Button("Update from Archive…") { appState.beginModUpdate(for: mod) }
                                .buttonStyle(.borderedProminent)
                        } else {
                            Text("Not installed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Update History (\(appState.modUpdateHistory.count))")
                .font(.headline)
            if appState.modUpdateHistory.isEmpty {
                Text("Completed transactional updates will appear here with their rollback backups.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.modUpdateHistory) { record in
                    HStack {
                        Image(systemName: record.status == .installed ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill")
                            .foregroundStyle(record.status == .installed ? Color.green : Color.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(record.modName)
                                .fontWeight(.medium)
                            Text("\(Version64(rawValue: record.previousVersion64).description) → \(Version64(rawValue: record.installedVersion64).description) • \(record.sourceArchiveName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(record.installedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Text(record.status == .installed ? "Installed" : "Restored")
                            .font(.caption.bold())
                        Button("Restore Previous") { restoreCandidate = record }
                            .disabled(record.status != .installed || appState.isUpdatingMod)
                    }
                    .padding(10)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func installedMod(uuid: String) -> ModInfo? {
        (appState.activeMods + appState.inactiveMods).first {
            ModIdentity.comparisonKey($0.uuid) == ModIdentity.comparisonKey(uuid)
                && $0.pakFilePath != nil
        }
    }
}

struct ModUpdatePlanView: View {
    let plan: ModUpdatePlan
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review Mod Update")
                .font(.title2.bold())
            Text("No live file has been changed. Installing creates a durable backup first, then verifies the committed PAK.")
                .foregroundStyle(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
                GridRow { Text("Mod").foregroundStyle(.secondary); Text(plan.targetName) }
                GridRow { Text("Archive").foregroundStyle(.secondary); Text(plan.sourceArchiveName) }
                GridRow {
                    Text("Version").foregroundStyle(.secondary)
                    Text("\(Version64(rawValue: plan.installedVersion64).description) → \(Version64(rawValue: plan.candidateVersion64).description)")
                        .font(.body.monospacedDigit())
                }
                GridRow { Text("Installed PAK").foregroundStyle(.secondary); Text(plan.installedPAK.path).font(.caption.monospaced()) }
                GridRow { Text("Candidate SHA-256").foregroundStyle(.secondary); Text(String(plan.candidateSHA256.prefix(16)) + "…").font(.caption.monospaced()) }
                GridRow {
                    Text("Load order").foregroundStyle(.secondary)
                    Text(plan.wasActive ? "Preserve active position \(plan.previousUserPosition ?? 1)" : "Remain inactive")
                }
            }
            .textSelection(.enabled)

            Label("The staged UUID matches the installed mod. Multi-PAK archives and metadata-free candidates are rejected.", systemImage: "checkmark.shield.fill")
                .foregroundStyle(.green)

            HStack {
                Button("Cancel", role: .cancel) { appState.cancelPendingModUpdate() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Install Update") {
                    Task { await appState.applyPendingModUpdate() }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(appState.isUpdatingMod)
            }
        }
        .padding(20)
        .frame(minWidth: 650)
        .interactiveDismissDisabled()
    }
}
