// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

// MARK: - Semantic Colors

extension Color {
    // Backgrounds
    static let bgSubtle = Color.primary.opacity(0.03)
    static let bgMuted = Color.primary.opacity(0.05)
    static let bgSelected = Color.accentColor.opacity(0.08)
    static let bgTag = Color.accentColor.opacity(0.15)

    // Severity backgrounds
    static let severityCriticalBg = Color.red.opacity(0.1)
    static let severityWarningBg = Color.yellow.opacity(0.1)

    // Borders & Chips
    static let chipBorder = Color.secondary.opacity(0.3)
    static let chipBorderActive = Color.secondary.opacity(0.5)
    static let chipBgUncategorized = Color.gray.opacity(0.15)
    static let borderMuted = Color.secondary.opacity(0.3)

    // Indicators
    static let unsavedDot = Color.white.opacity(0.9)

    // Stat box
    static let statBoxBg = Color.secondary.opacity(0.08)
}

// MARK: - Spacing

enum Spacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let sm: CGFloat = 6
    static let md: CGFloat = 8
    static let lg: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 24
}

// MARK: - View Modifiers

/// Applies `.symbolEffect(.bounce)` on macOS 14+; no-op on macOS 13.
struct SymbolBounceModifier: ViewModifier {
    let trigger: Int

    func body(content: Content) -> some View {
        if #available(macOS 14, *) {
            content.symbolEffect(.bounce, value: trigger)
        } else {
            content
        }
    }
}

// MARK: - Severity Styling

extension ModWarning.Severity {
    var color: Color {
        switch self {
        case .critical: return .red
        case .warning:  return .yellow
        case .info:     return .blue
        }
    }

    var backgroundColor: Color {
        switch self {
        case .critical: return .severityCriticalBg
        case .warning:  return .severityWarningBg
        case .info:     return .blue.opacity(0.1)
        }
    }
}
