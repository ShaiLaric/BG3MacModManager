import Foundation

/// Represents a detected issue with the mod configuration.
struct ModWarning: Identifiable, Equatable {
    let id: UUID
    let severity: Severity
    let category: Category
    let message: String
    let detail: String
    let affectedModUUIDs: [String]
    let suggestedAction: SuggestedAction?

    init(
        severity: Severity,
        category: Category,
        message: String,
        detail: String = "",
        affectedModUUIDs: [String] = [],
        suggestedAction: SuggestedAction? = nil
    ) {
        self.id = UUID()
        self.severity = severity
        self.category = category
        self.message = message
        self.detail = detail
        self.affectedModUUIDs = affectedModUUIDs
        self.suggestedAction = suggestedAction
    }

    static func == (lhs: ModWarning, rhs: ModWarning) -> Bool {
        lhs.id == rhs.id
    }

    enum Severity: Int, Comparable, CaseIterable {
        case info = 1        // Informational
        case warning = 2     // May cause issues
        case critical = 3    // Will crash the game

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }

        var icon: String {
            switch self {
            case .critical: return "xmark.octagon.fill"
            case .warning:  return "exclamationmark.triangle.fill"
            case .info:     return "info.circle.fill"
            }
        }
    }

    enum Category: String, CaseIterable {
        case duplicateUUID       = "Duplicate UUID"
        case missingDependency   = "Missing Dependency"
        case wrongLoadOrder      = "Wrong Load Order"
        case circularDependency  = "Circular Dependency"
        case conflictingMods     = "Mod Conflict"
        case phantomMod          = "Phantom Mod"
        case seRequired          = "Script Extender Required"
        case noMetadata          = "No Metadata"
    }

    enum SuggestedAction: Equatable {
        case autoSort
        case deactivateMod(uuid: String)
        case installDependency(name: String)
        case installScriptExtender
    }
}
