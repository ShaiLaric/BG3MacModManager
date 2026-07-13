// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

struct LaunchReadinessView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if appState.isCheckingReadiness && appState.readinessReport == nil {
                Spacer()
                ProgressView("Checking launch readiness…")
                Spacer()
            } else if let report = appState.readinessReport {
                reportContent(report)
            } else {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 38))
                        .foregroundStyle(.secondary)
                    Text("Launch readiness has not been checked")
                        .font(.headline)
                    Button("Check Now") {
                        Task { await appState.refreshLaunchReadiness() }
                    }
                }
                Spacer()
            }
        }
        .task {
            if appState.readinessReport == nil {
                _ = await appState.refreshLaunchReadiness()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Launch Readiness")
                    .font(.title2.bold())
                Text("A point-in-time preflight check of the current load order and installation")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if appState.isCheckingReadiness {
                ProgressView()
                    .controlSize(.small)
            }
            Button {
                Task { await appState.refreshLaunchReadiness() }
            } label: {
                Label("Recheck", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isCheckingReadiness)

            Button {
                Task { await appState.launchGame() }
            } label: {
                Label("Launch BG3", systemImage: "play.fill")
            }
            .disabled(appState.isCheckingReadiness || !appState.isGameInstalled)
        }
        .padding()
    }

    private func reportContent(_ report: LaunchReadinessReport) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                reportSummary(report)

                if report.findings.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No launch issues found")
                                .font(.headline)
                            Text("The checks completed for this snapshot did not find anything requiring attention.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    ForEach(ReadinessCategory.allCases, id: \.self) { category in
                        let findings = report.findings.filter { $0.category == category }
                        if !findings.isEmpty {
                            findingSection(category, findings: findings)
                        }
                    }
                }

                checkCoverage(report.checks)
            }
            .padding()
        }
    }

    private func reportSummary(_ report: LaunchReadinessReport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: stateIcon(report.overallState))
                .font(.system(size: 30))
                .foregroundStyle(stateColor(report.overallState))
            VStack(alignment: .leading, spacing: 2) {
                Text(report.overallState.rawValue)
                    .font(.title3.bold())
                Text("Checked \(report.generatedAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(report.findings.filter { $0.severity == .critical }.count) critical")
                .foregroundStyle(.red)
            Text("\(report.findings.filter { $0.severity == .warning }.count) warnings")
                .foregroundStyle(.orange)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report.diagnosticSummary, forType: .string)
                appState.statusMessage = "Copied launch readiness diagnostics"
            } label: {
                Label("Copy Diagnostics", systemImage: "doc.on.doc")
            }
        }
        .padding()
        .background(stateColor(report.overallState).opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    private func findingSection(_ category: ReadinessCategory, findings: [ReadinessFinding]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(category.rawValue)
                .font(.headline)
            ForEach(findings) { finding in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: severityIcon(finding.severity))
                        .foregroundStyle(severityColor(finding.severity))
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(finding.title)
                            .fontWeight(.medium)
                        Text(finding.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 12)
                    if let action = finding.action {
                        Button(action.title) {
                            Task { await appState.performReadinessAction(action) }
                        }
                        .controlSize(.small)
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func checkCoverage(_ checks: [ReadinessCheckStatus]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Check Coverage")
                .font(.headline)
            ForEach(checks) { check in
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: checkIcon(check.state))
                        .foregroundStyle(checkColor(check.state))
                        .frame(width: 18)
                    Text(check.name)
                    Spacer()
                    Text(check.state.rawValue.capitalized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let detail = check.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 300, alignment: .trailing)
                    }
                }
            }
        }
        .padding()
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
    }

    private func stateIcon(_ state: LaunchReadinessReport.OverallState) -> String {
        switch state {
        case .ready: return "checkmark.shield.fill"
        case .review: return "exclamationmark.shield.fill"
        case .critical: return "xmark.shield.fill"
        }
    }

    private func stateColor(_ state: LaunchReadinessReport.OverallState) -> Color {
        switch state {
        case .ready: return .green
        case .review: return .orange
        case .critical: return .red
        }
    }

    private func severityIcon(_ severity: ReadinessSeverity) -> String {
        switch severity {
        case .information: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .critical: return "xmark.octagon.fill"
        }
    }

    private func severityColor(_ severity: ReadinessSeverity) -> Color {
        switch severity {
        case .information: return .blue
        case .warning: return .orange
        case .critical: return .red
        }
    }

    private func checkIcon(_ state: ReadinessCheckStatus.State) -> String {
        switch state {
        case .completed: return "checkmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        case .unavailable: return "questionmark.circle.fill"
        case .stale: return "clock.badge.exclamationmark.fill"
        }
    }

    private func checkColor(_ state: ReadinessCheckStatus.State) -> Color {
        switch state {
        case .completed: return .green
        case .skipped, .unavailable: return .secondary
        case .stale: return .orange
        }
    }
}

struct LaunchReadinessPreflightView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "xmark.shield.fill")
                    .font(.title)
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Critical launch issues found")
                        .font(.title3.bold())
                    Text("The game may fail to load this mod configuration.")
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(appState.readinessReport?.criticalFindings ?? []) { finding in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(finding.title).fontWeight(.medium)
                            Text(finding.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(minHeight: 140, maxHeight: 320)

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button("Review Readiness") {
                    appState.navigateToSidebarItem = "readiness"
                    dismiss()
                }
                Button("Launch Anyway", role: .destructive) {
                    Task { await appState.launchDespiteReadiness() }
                }
            }
        }
        .padding(20)
        .frame(minWidth: 560)
    }
}
