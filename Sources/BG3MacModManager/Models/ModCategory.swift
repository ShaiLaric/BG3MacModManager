// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Load order tier for category-aware smart sorting.
/// Based on the BG3 Modding Community Wiki's 5-tier convention:
/// https://wiki.bg3.community/en/Tutorials/Mod-Use/general-load-order
enum ModCategory: Int, Codable, CaseIterable, Comparable {
    /// Frameworks & libraries that other mods depend on. Load first.
    case framework = 1
    /// Gameplay, action, and bug-fix mods.
    case gameplay = 2
    /// Content extensions: new classes, subclasses, spells, feats.
    case contentExtension = 3
    /// Visual and cosmetic mods: appearance, textures, UI.
    case visual = 4
    /// Late loaders: compatibility patches, spell list combiners. Load last.
    case lateLoader = 5

    static func < (lhs: ModCategory, rhs: ModCategory) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .framework:        return "Framework"
        case .gameplay:         return "Gameplay"
        case .contentExtension: return "Content"
        case .visual:           return "Visual"
        case .lateLoader:       return "Late Loader"
        }
    }

    var color: Color {
        switch self {
        case .framework:        return .purple
        case .gameplay:         return .blue
        case .contentExtension: return .green
        case .visual:           return .pink
        case .lateLoader:       return .orange
        }
    }

    var icon: String {
        switch self {
        case .framework:        return "wrench.and.screwdriver"
        case .gameplay:         return "gamecontroller"
        case .contentExtension: return "plus.square.on.square"
        case .visual:           return "paintbrush"
        case .lateLoader:       return "arrow.down.to.line"
        }
    }

    /// Detailed description for tooltips explaining what each tier means.
    var tooltip: String {
        switch self {
        case .framework:
            return "Tier 1 — Framework: Libraries and APIs that other mods depend on (e.g., ImpUI, Community Library, MCM). These load first so dependents can build on them."
        case .gameplay:
            return "Tier 2 — Gameplay: Mods that change game mechanics, add items, fix bugs, or tweak balance. Loads after frameworks so it can use their APIs."
        case .contentExtension:
            return "Tier 3 — Content: Mods that add new classes, subclasses, spells, feats, or races. Loads in the middle of the order."
        case .visual:
            return "Tier 4 — Visual: Cosmetic mods like hair, appearance, dyes, and textures. Loads late so visual changes aren't overwritten."
        case .lateLoader:
            return "Tier 5 — Late Loader: Compatibility patches and combiners (e.g., Compatibility Framework, Spell List Combiner). These load last to reconcile conflicts between earlier mods."
        }
    }
}
