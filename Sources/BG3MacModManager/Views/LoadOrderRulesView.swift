// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

struct LoadOrderRuleEditorRequest: Identifiable {
    let id = UUID()
    var sourceUUID: String?
    var kind: LoadOrderRule.Kind
    var position: Int?
}

struct LoadOrderRulesView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var editorRequest: LoadOrderRuleEditorRequest?

    private var violationsByRuleID: [UUID: LoadOrderRuleViolation] {
        Dictionary(
            uniqueKeysWithValues: LoadOrderSolver.violations(
                mods: appState.activeMods,
                rules: appState.loadOrderRules
            ).map { ($0.ruleID, $0) }
        )
    }

    private var solverConflict: LoadOrderSolver.Conflict? {
        let userMods = appState.activeMods.filter { !$0.isBasicGameModule }
        guard case .conflict(let conflict) = appState.loadOrderSolver.solve(
            mods: userMods,
            rules: appState.loadOrderRules,
            mode: .dependenciesOnly
        ) else { return nil }
        return conflict
    }

    var body: some View {
        NavigationStack {
            Group {
                if appState.loadOrderRules.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.up.arrow.down.square")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No Load-Order Rules")
                            .font(.title3.bold())
                        Text("Add a persistent before/after rule or pin a mod to a position.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(appState.loadOrderRules) { rule in
                            ruleRow(rule)
                        }
                    }
                }
            }
            .navigationTitle("Load-Order Rules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorRequest = LoadOrderRuleEditorRequest(
                            sourceUUID: nil,
                            kind: .before,
                            position: nil
                        )
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                }
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .sheet(item: $editorRequest) { request in
            LoadOrderRuleEditorView(request: request)
                .environmentObject(appState)
        }
    }

    private func ruleRow(_ rule: LoadOrderRule) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: { appState.setLoadOrderRuleEnabled(rule, enabled: $0) }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(description(for: rule))
                    .font(.body)

                HStack(spacing: 6) {
                    let status = status(for: rule)
                    Image(systemName: status.icon)
                    Text(status.text)
                }
                .font(.caption)
                .foregroundStyle(status(for: rule).color)
            }

            Spacer()

            Button(role: .destructive) {
                appState.deleteLoadOrderRule(rule)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help("Delete this rule")
        }
        .padding(.vertical, 4)
    }

    private func description(for rule: LoadOrderRule) -> String {
        let source = appState.displayName(forModUUID: rule.sourceUUID)
        switch rule.kind {
        case .before:
            return "\(source) always loads before \(appState.displayName(forModUUID: rule.targetUUID ?? ""))"
        case .after:
            return "\(source) always loads after \(appState.displayName(forModUUID: rule.targetUUID ?? ""))"
        case .pinPosition:
            return "\(source) is pinned to user-mod position \(rule.position ?? 0)"
        case .pinFirst:
            return "\(source) is pinned first"
        case .pinLast:
            return "\(source) is pinned last"
        }
    }

    private func status(for rule: LoadOrderRule) -> (text: String, icon: String, color: Color) {
        guard rule.isEnabled else {
            return ("Disabled", "pause.circle", .secondary)
        }
        guard appState.isInstalledModUUID(rule.sourceUUID) else {
            return ("Dormant — source mod is not installed", "moon.zzz", .secondary)
        }
        if let target = rule.targetUUID, !appState.isInstalledModUUID(target) {
            return ("Dormant — target mod is not installed", "moon.zzz", .secondary)
        }
        if let conflict = solverConflict, conflict.ruleIDs.contains(rule.id) {
            return (conflict.message, "xmark.octagon.fill", .red)
        }
        if let violation = violationsByRuleID[rule.id] {
            return (violation.message, "exclamationmark.triangle.fill", .orange)
        }
        return ("Satisfied or waiting for activation", "checkmark.circle.fill", .green)
    }
}

struct LoadOrderRuleEditorView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var sourceUUID: String
    @State private var kind: LoadOrderRule.Kind
    @State private var targetUUID: String
    @State private var position: Int

    init(request: LoadOrderRuleEditorRequest) {
        _sourceUUID = State(initialValue: request.sourceUUID ?? "")
        _kind = State(initialValue: request.kind)
        _targetUUID = State(initialValue: "")
        _position = State(initialValue: request.position ?? 1)
    }

    private var availableMods: [ModInfo] {
        var seen = Set<String>()
        return (appState.activeMods + appState.inactiveMods)
            .filter { !$0.isBasicGameModule }
            .filter { seen.insert(ModIdentity.comparisonKey($0.uuid)).inserted }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var targetMods: [ModInfo] {
        availableMods.filter {
            ModIdentity.comparisonKey($0.uuid) != ModIdentity.comparisonKey(sourceUUID)
        }
    }

    private var maximumPosition: Int {
        let activeUserMods = appState.activeMods.filter { !$0.isBasicGameModule }.count
        let sourceIsActive = appState.activeMods.contains {
            ModIdentity.comparisonKey($0.uuid) == ModIdentity.comparisonKey(sourceUUID)
        }
        return max(1, activeUserMods + (sourceIsActive ? 0 : 1))
    }

    private var canSave: Bool {
        guard !sourceUUID.isEmpty else { return false }
        if kind.needsTarget { return !targetUUID.isEmpty }
        if kind.needsPosition { return position > 0 && position <= maximumPosition }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Add Load-Order Rule")
                .font(.title2.bold())

            Picker("Mod", selection: $sourceUUID) {
                Text("Choose a mod").tag("")
                ForEach(availableMods) { mod in
                    Text(mod.name).tag(mod.uuid)
                }
            }

            Picker("Rule", selection: $kind) {
                ForEach(LoadOrderRule.Kind.allCases, id: \.self) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            if kind.needsTarget {
                Picker(kind == .before ? "Load before" : "Load after", selection: $targetUUID) {
                    Text("Choose another mod").tag("")
                    ForEach(targetMods) { mod in
                        Text(mod.name).tag(mod.uuid)
                    }
                }
            }

            if kind.needsPosition {
                Stepper(
                    "User-mod position: \(position)",
                    value: $position,
                    in: 1...maximumPosition
                )
            }

            Text("Persistent rules are global. Missing mods leave a dormant rule that becomes active if the mod is installed again.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save Rule") {
                    if appState.addLoadOrderRule(
                        kind: kind,
                        sourceUUID: sourceUUID,
                        targetUUID: kind.needsTarget ? targetUUID : nil,
                        position: kind.needsPosition ? position : nil
                    ) {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            if sourceUUID.isEmpty, let first = availableMods.first {
                sourceUUID = first.uuid
            }
            if targetUUID.isEmpty, let first = targetMods.first {
                targetUUID = first.uuid
            }
            position = min(max(position, 1), maximumPosition)
        }
        .onChange(of: sourceUUID) { _ in
            if targetMods.contains(where: { $0.uuid == targetUUID }) == false {
                targetUUID = targetMods.first?.uuid ?? ""
            }
            position = min(max(position, 1), maximumPosition)
        }
        .onChange(of: kind) { _ in
            position = min(max(position, 1), maximumPosition)
        }
    }
}
