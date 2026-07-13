// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Optional one-based placement control used when activating a single mod.
struct ActivationPositionView: View {
    let mod: ModInfo
    let maximumPosition: Int
    let onActivate: (Int?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var positionText = ""
    @FocusState private var positionFieldFocused: Bool

    private var trimmedPosition: String {
        positionText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var requestedPosition: Int? {
        guard !trimmedPosition.isEmpty else { return nil }
        return Int(trimmedPosition)
    }

    private var isValid: Bool {
        trimmedPosition.isEmpty
            || requestedPosition.map { (1...maximumPosition).contains($0) } == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Activate Mod")
                .font(.title2.bold())

            Text(mod.name)
                .font(.headline)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 6) {
                TextField("Load-order number (optional)", text: $positionText)
                    .textFieldStyle(.roundedBorder)
                    .focused($positionFieldFocused)
                    .onSubmit(activateIfValid)

                Text("Enter 1–\(maximumPosition), or leave blank to add the mod at the end.")
                    .font(.caption)
                    .foregroundStyle(isValid ? Color.secondary : Color.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Activate") {
                    activateIfValid()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 390)
        .onAppear {
            positionFieldFocused = true
        }
    }

    private func activateIfValid() {
        guard isValid else { return }
        onActivate(requestedPosition)
        dismiss()
    }
}
