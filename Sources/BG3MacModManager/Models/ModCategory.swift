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
}
