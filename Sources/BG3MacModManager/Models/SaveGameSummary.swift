// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct SaveModEntry: Identifiable, Codable, Equatable, Sendable {
    let uuid: String
    let name: String
    let folder: String
    let version64: Int64
    let md5: String

    var id: String { uuid }
}

struct SaveGameSummary: Identifiable, Equatable, Sendable {
    let id: String
    let campaignID: String
    let campaignName: String
    let displayName: String
    let relativePath: String
    let fileURL: URL
    let screenshotURL: URL?
    let modifiedAt: Date
    let fileSize: Int64
    let fileResourceIdentity: String?
    let mods: [SaveModEntry]
    let modListFingerprint: String?
    let readError: String?

    var isReadable: Bool { readError == nil }
}

struct SaveProfileAssociation: Identifiable, Codable, Equatable, Sendable {
    enum TargetKind: String, Codable, Sendable {
        case campaign
        case save
    }

    let id: UUID
    let targetKind: TargetKind
    let targetID: String
    var targetDisplayName: String
    var lastKnownRelativePath: String?
    var profileID: UUID
    var lastSeenSaveTimestamp: Date?
    var lastSeenModListFingerprint: String?
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        targetKind: TargetKind,
        targetID: String,
        targetDisplayName: String,
        lastKnownRelativePath: String?,
        profileID: UUID,
        lastSeenSaveTimestamp: Date?,
        lastSeenModListFingerprint: String?,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.targetKind = targetKind
        self.targetID = targetID
        self.targetDisplayName = targetDisplayName
        self.lastKnownRelativePath = lastKnownRelativePath
        self.profileID = profileID
        self.lastSeenSaveTimestamp = lastSeenSaveTimestamp
        self.lastSeenModListFingerprint = lastSeenModListFingerprint
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ResolvedSaveProfileAssociation: Equatable, Sendable {
    let association: SaveProfileAssociation
    let matchedKind: SaveProfileAssociation.TargetKind
}

struct SaveProfileComparison: Equatable, Sendable {
    struct VersionDifference: Equatable, Sendable {
        let uuid: String
        let name: String
        let expectedVersion64: Int64
        let installedVersion64: Int64
    }

    let missingInstalledUUIDs: [String]
    let extraActiveUUIDs: [String]
    let versionDifferences: [VersionDifference]
    let currentOrderDiffers: Bool
    let saveOrderDiffersFromProfile: Bool

    var hasCurrentMismatch: Bool {
        !missingInstalledUUIDs.isEmpty || !extraActiveUUIDs.isEmpty
            || !versionDifferences.isEmpty || currentOrderDiffers
    }

    var summary: String {
        var parts: [String] = []
        if !missingInstalledUUIDs.isEmpty { parts.append("\(missingInstalledUUIDs.count) profile mod(s) are not installed") }
        if !extraActiveUUIDs.isEmpty { parts.append("\(extraActiveUUIDs.count) extra mod(s) are active") }
        if !versionDifferences.isEmpty { parts.append("\(versionDifferences.count) installed version(s) differ") }
        if currentOrderDiffers { parts.append("the active load order differs") }
        if saveOrderDiffersFromProfile { parts.append("the save recorded a different load order") }
        return parts.isEmpty ? "The current setup matches the associated profile." : parts.joined(separator: "; ").capitalized + "."
    }
}
