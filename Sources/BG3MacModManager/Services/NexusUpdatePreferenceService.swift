// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

final class NexusUpdatePreferenceService {
    private let store: VersionedJSONStore<NexusUpdatePreferencePayload>

    init(url: URL = FileLocations.nexusUpdatePreferencesFile) {
        store = VersionedJSONStore(url: url, currentSchemaVersion: 1)
    }

    func loadPreferences() throws -> [String: NexusUpdatePreference] {
        let preferences = try store.load()?.preferencesByUUID ?? [:]
        return Dictionary(
            preferences.map { (ModIdentity.comparisonKey($0.key), $0.value) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    func savePreferences(_ preferences: [String: NexusUpdatePreference]) throws {
        let normalized = Dictionary(
            preferences.map { (ModIdentity.comparisonKey($0.key), $0.value) },
            uniquingKeysWith: { _, latest in latest }
        )
        try store.save(NexusUpdatePreferencePayload(preferencesByUUID: normalized))
    }

    func ignoring(
        _ result: NexusUpdateResult,
        in preferences: [String: NexusUpdatePreference],
        now: Date = Date()
    ) -> [String: NexusUpdatePreference] {
        let key = ModIdentity.comparisonKey(result.modUUID)
        var updated = preferences
        var preference = updated[key] ?? .enabled(now: now)
        preference.ignoredVersion = result.latestVersion
        preference.ignoredNexusModID = result.nexusModID
        preference.updatedAt = now
        updated[key] = preference
        return updated
    }

    func clearingIgnoredVersion(
        for modUUID: String,
        in preferences: [String: NexusUpdatePreference],
        now: Date = Date()
    ) -> [String: NexusUpdatePreference] {
        let key = ModIdentity.comparisonKey(modUUID)
        guard var preference = preferences[key] else { return preferences }
        var updated = preferences
        preference.ignoredVersion = nil
        preference.ignoredNexusModID = nil
        preference.updatedAt = now
        if preference.isEmpty {
            updated.removeValue(forKey: key)
        } else {
            updated[key] = preference
        }
        return updated
    }

    func settingChecksDisabled(
        _ disabled: Bool,
        for modUUID: String,
        in preferences: [String: NexusUpdatePreference],
        now: Date = Date()
    ) -> [String: NexusUpdatePreference] {
        let key = ModIdentity.comparisonKey(modUUID)
        var updated = preferences
        var preference = updated[key] ?? .enabled(now: now)
        preference.checksDisabled = disabled
        preference.updatedAt = now
        if preference.isEmpty {
            updated.removeValue(forKey: key)
        } else {
            updated[key] = preference
        }
        return updated
    }
}
