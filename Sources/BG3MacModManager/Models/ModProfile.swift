import Foundation

/// A saved mod configuration (load order + active mods).
struct ModProfile: Identifiable, Codable {
    let id: UUID
    var name: String
    var createdAt: Date
    var updatedAt: Date

    /// Ordered list of active mod UUIDs (defines load order).
    var activeModUUIDs: [String]

    /// Full metadata for each mod in the profile (for portability).
    var mods: [ModProfileEntry]

    init(name: String, activeModUUIDs: [String], mods: [ModProfileEntry]) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.updatedAt = Date()
        self.activeModUUIDs = activeModUUIDs
        self.mods = mods
    }
}

/// Minimal mod metadata stored in a profile for reconstruction.
struct ModProfileEntry: Codable, Identifiable {
    let uuid: String
    var folder: String
    var name: String
    var version64: Int64
    var md5: String

    var id: String { uuid }

    init(from mod: ModInfo) {
        self.uuid = mod.uuid
        self.folder = mod.folder
        self.name = mod.name
        self.version64 = mod.version64
        self.md5 = mod.md5
    }
}
