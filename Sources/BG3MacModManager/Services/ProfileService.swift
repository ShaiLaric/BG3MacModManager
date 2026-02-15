// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Saves and loads mod profiles (named load order configurations).
final class ProfileService {

    enum ProfileError: Error, LocalizedError {
        case saveFailed(String)
        case loadFailed(String)
        case profileNotFound(String)

        var errorDescription: String? {
            switch self {
            case .saveFailed(let msg): return "Failed to save profile: \(msg)"
            case .loadFailed(let msg): return "Failed to load profile: \(msg)"
            case .profileNotFound(let name): return "Profile not found: \(name)"
            }
        }
    }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Save

    /// Save a profile with the current active mods and their load order.
    func save(name: String, activeMods: [ModInfo]) throws -> ModProfile {
        let entries = activeMods.map { ModProfileEntry(from: $0) }
        let profile = ModProfile(
            name: name,
            activeModUUIDs: activeMods.map(\.uuid),
            mods: entries
        )

        let data = try encoder.encode(profile)
        let url = profileURL(for: profile)
        try FileLocations.ensureDirectoryExists(FileLocations.profilesDirectory)
        try data.write(to: url, options: .atomic)

        return profile
    }

    // MARK: - Load

    /// List all saved profiles.
    func listProfiles() throws -> [ModProfile] {
        let dir = FileLocations.profilesDirectory
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        let jsonFiles = files.filter { $0.pathExtension == "json" }

        return jsonFiles.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let profile = try? decoder.decode(ModProfile.self, from: data) else {
                return nil
            }
            return profile
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Load a specific profile by ID.
    func load(id: UUID) throws -> ModProfile {
        let profiles = try listProfiles()
        guard let profile = profiles.first(where: { $0.id == id }) else {
            throw ProfileError.profileNotFound(id.uuidString)
        }
        return profile
    }

    // MARK: - Delete

    /// Delete a profile.
    func delete(profile: ModProfile) throws {
        let url = profileURL(for: profile)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Rename

    /// Rename a profile. Deletes the old file and writes a new one with the updated name.
    func rename(profile: ModProfile, to newName: String) throws -> ModProfile {
        let oldURL = profileURL(for: profile)
        if FileManager.default.fileExists(atPath: oldURL.path) {
            try FileManager.default.removeItem(at: oldURL)
        }

        var updated = profile
        updated.name = newName
        updated.updatedAt = Date()

        let data = try encoder.encode(updated)
        let newURL = profileURL(for: updated)
        try FileLocations.ensureDirectoryExists(FileLocations.profilesDirectory)
        try data.write(to: newURL, options: .atomic)

        return updated
    }

    // MARK: - Update

    /// Overwrite a profile's active mod list with the current load order.
    func update(profile: ModProfile, activeMods: [ModInfo]) throws -> ModProfile {
        let oldURL = profileURL(for: profile)
        if FileManager.default.fileExists(atPath: oldURL.path) {
            try FileManager.default.removeItem(at: oldURL)
        }

        let entries = activeMods.map { ModProfileEntry(from: $0) }
        var updated = profile
        updated.activeModUUIDs = activeMods.map(\.uuid)
        updated.mods = entries
        updated.updatedAt = Date()

        let data = try encoder.encode(updated)
        let newURL = profileURL(for: updated)
        try FileLocations.ensureDirectoryExists(FileLocations.profilesDirectory)
        try data.write(to: newURL, options: .atomic)

        return updated
    }

    // MARK: - Export / Import

    /// Export a profile to a specific URL (for sharing).
    func export(profile: ModProfile, to url: URL) throws {
        let data = try encoder.encode(profile)
        try data.write(to: url, options: .atomic)
    }

    /// Import a profile from a JSON file.
    func importProfile(from url: URL) throws -> ModProfile {
        let data = try Data(contentsOf: url)
        let profile = try decoder.decode(ModProfile.self, from: data)

        // Save to profiles directory
        let savedData = try encoder.encode(profile)
        let savedURL = profileURL(for: profile)
        try FileLocations.ensureDirectoryExists(FileLocations.profilesDirectory)
        try savedData.write(to: savedURL, options: .atomic)

        return profile
    }

    // MARK: - Helpers

    private func profileURL(for profile: ModProfile) -> URL {
        let sanitizedName = profile.name
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return FileLocations.profilesDirectory
            .appendingPathComponent("\(sanitizedName)-\(profile.id.uuidString).json")
    }
}

// MARK: - Shared JSONEncoder

extension JSONEncoder {
    /// Pre-configured encoder matching the app's profile JSON format.
    static var bg3PrettyPrinted: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
