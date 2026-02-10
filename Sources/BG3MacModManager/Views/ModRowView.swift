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

                    if mod.requiresScriptExtender {
                        Text("SE")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange, in: RoundedRectangle(cornerRadius: 3))
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
                    }
                }
            }

            Spacer()

            // Warnings
            if !appState.missingDependencies(for: mod).isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                    .help("Missing dependencies")
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
}
