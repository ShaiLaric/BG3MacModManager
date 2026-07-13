// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct SaveProfileAssociationPayload: Codable, Equatable {
    var associations: [SaveProfileAssociation]
}

final class SaveProfileAssociationService {
    private let store: VersionedJSONStore<SaveProfileAssociationPayload>

    init(url: URL = FileLocations.saveProfileAssociationsFile) {
        store = VersionedJSONStore(url: url, currentSchemaVersion: 1)
    }

    func loadAssociations() throws -> [SaveProfileAssociation] {
        try store.load()?.associations ?? []
    }

    func saveAssociations(_ associations: [SaveProfileAssociation]) throws {
        try store.save(SaveProfileAssociationPayload(associations: associations))
    }

    func upserting(
        kind: SaveProfileAssociation.TargetKind,
        save: SaveGameSummary,
        profileID: UUID,
        in associations: [SaveProfileAssociation],
        now: Date = Date()
    ) -> [SaveProfileAssociation] {
        let targetID = kind == .save ? save.id : save.campaignID
        let displayName = kind == .save ? save.displayName : save.campaignName
        var updated = associations
        if let index = updated.firstIndex(where: { $0.targetKind == kind && $0.targetID == targetID }) {
            updated[index].targetDisplayName = displayName
            updated[index].lastKnownRelativePath = save.relativePath
            updated[index].profileID = profileID
            updated[index].lastSeenSaveTimestamp = save.modifiedAt
            updated[index].lastSeenModListFingerprint = save.modListFingerprint
            updated[index].updatedAt = now
        } else {
            updated.append(SaveProfileAssociation(
                targetKind: kind,
                targetID: targetID,
                targetDisplayName: displayName,
                lastKnownRelativePath: save.relativePath,
                profileID: profileID,
                lastSeenSaveTimestamp: save.modifiedAt,
                lastSeenModListFingerprint: save.modListFingerprint,
                createdAt: now,
                updatedAt: now
            ))
        }
        return updated
    }

    func resolvedAssociation(
        for save: SaveGameSummary,
        in associations: [SaveProfileAssociation]
    ) -> ResolvedSaveProfileAssociation? {
        if let exact = associations.first(where: { $0.targetKind == .save && $0.targetID == save.id }) {
            return ResolvedSaveProfileAssociation(association: exact, matchedKind: .save)
        }
        if let campaign = associations.first(where: {
            $0.targetKind == .campaign && $0.targetID == save.campaignID
        }) {
            return ResolvedSaveProfileAssociation(association: campaign, matchedKind: .campaign)
        }
        return nil
    }
}
