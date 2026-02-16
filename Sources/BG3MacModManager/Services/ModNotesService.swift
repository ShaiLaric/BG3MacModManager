// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Persists per-mod user notes to a JSON file.
/// Follows the same persistence pattern as NexusURLService.
final class ModNotesService {

    // MARK: - Public API

    /// Get the stored note for a mod, if any.
    func note(for modUUID: String) -> String? {
        notes[modUUID]
    }

    /// Set or update the note for a mod. Pass nil or empty/whitespace-only string to clear.
    func setNote(_ text: String?, for modUUID: String) {
        if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes[modUUID] = text
        } else {
            notes.removeValue(forKey: modUUID)
        }
        save()
    }

    /// All stored notes (for bulk lookup / export).
    func allNotes() -> [String: String] {
        notes
    }

    // MARK: - Persistence

    private var notes: [String: String] = [:]

    private static var storageURL: URL {
        FileLocations.appSupportDirectory.appendingPathComponent("mod_notes.json")
    }

    init() {
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.storageURL),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data) else {
            return
        }
        notes = decoded
    }

    private func save() {
        do {
            try FileLocations.ensureDirectoryExists(FileLocations.appSupportDirectory)
            let data = try JSONEncoder().encode(notes)
            try data.write(to: Self.storageURL, options: .atomic)
        } catch {
            // Non-fatal: notes just won't persist
        }
    }
}
