// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Persists per-mod user notes to a JSON file.
/// Follows the same persistence pattern as NexusURLService.
final class ModNotesService {

    // MARK: - Public API

    /// Get the stored note for a mod, if any.
    func note(for modUUID: String) -> String? {
        notes[ModIdentity.comparisonKey(modUUID)]
    }

    /// Set or update the note for a mod. Pass nil or empty/whitespace-only string to clear.
    @discardableResult
    func setNote(_ text: String?, for modUUID: String) -> Bool {
        let previous = notes
        let modUUID = ModIdentity.comparisonKey(modUUID)
        if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes[modUUID] = text
        } else {
            notes.removeValue(forKey: modUUID)
        }
        do {
            try save()
            return true
        } catch {
            notes = previous
            return false
        }
    }

    /// All stored notes (for bulk lookup / export).
    func allNotes() -> [String: String] {
        notes
    }

    // MARK: - Persistence

    private var notes: [String: String] = [:]

    private let storageURL: URL

    init(storageURL: URL? = nil) {
        self.storageURL = storageURL
            ?? FileLocations.appSupportDirectory.appendingPathComponent("mod_notes.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        notes = Dictionary(
            decoded.map { (ModIdentity.comparisonKey($0.key), $0.value) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    private func save() throws {
        try FileLocations.ensureDirectoryExists(storageURL.deletingLastPathComponent())
        let data = try JSONEncoder().encode(notes)
        try data.write(to: storageURL, options: .atomic)
    }
}
