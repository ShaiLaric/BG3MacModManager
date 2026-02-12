import SwiftUI

/// A single row in the mod list showing mod name, author, and status indicators.
struct ModRowView: View {
    let mod: ModInfo
    let isActive: Bool
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 10) {
            // Load order number (for active mods)
            if isActive, let index = appState.activeMods.firstIndex(where: { $0.uuid == mod.uuid }) {
                Text("\(index + 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 24, alignment: .trailing)
            }

            // Mod info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mod.name)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if let category = mod.category {
                        Text(category.displayName)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(category.color, in: RoundedRectangle(cornerRadius: 3))
                            .help(category.tooltip)
                    }

                    if mod.requiresScriptExtender {
                        Text("SE")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 3))
                            .help("This mod requires bg3se-macos (Script Extender) to be deployed. The game will crash without it.")
                    }
                }

                HStack(spacing: 8) {
                    if mod.author != "Unknown" {
                        Text(mod.author)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text("v\(mod.version.description)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)

                    if mod.metadataSource == .filename {
                        Text("(no metadata)")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("This mod's PAK contains no meta.lsx and no info.json was found. UUID, version, and dependencies are unknown.")
                    }
                }
            }

            Spacer()

            // Warnings (severity-aware)
            let modWarnings = appState.warnings(for: mod)
            if !modWarnings.isEmpty {
                let maxSeverity = modWarnings.max(by: { $0.severity < $1.severity })?.severity ?? .info
                Image(systemName: maxSeverity.icon)
                    .foregroundStyle(colorForSeverity(maxSeverity))
                    .help(modWarnings.map(\.message).joined(separator: "\n"))
            }

            // Activate/Deactivate button
            if isActive && !mod.isBasicGameModule {
                Button {
                    appState.deactivateMod(mod)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Deactivate")
            } else if !isActive {
                Button {
                    appState.activateMod(mod)
                } label: {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .help("Activate")
            }
        }
        .padding(.vertical, 2)
    }

    private func colorForSeverity(_ severity: ModWarning.Severity) -> Color {
        switch severity {
        case .critical: return .red
        case .warning:  return .yellow
        case .info:     return .blue
        }
    }
}
