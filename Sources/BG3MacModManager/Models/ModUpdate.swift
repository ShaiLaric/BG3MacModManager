// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct ModUpdatePlan: Identifiable, Sendable {
    let id: UUID
    let targetUUID: String
    let targetName: String
    let installedPAK: URL
    let candidatePAK: URL
    let candidateInfoJSON: URL?
    let stagingDirectory: URL
    let sourceArchiveName: String
    let installedVersion64: Int64
    let candidateVersion64: Int64
    let installedSHA256: String
    let candidateSHA256: String
    let wasActive: Bool
    let previousUserPosition: Int?
    let nexusURL: String?

    var versionChanges: Bool { installedVersion64 != candidateVersion64 }
}

struct ModUpdateBackupItem: Codable, Equatable, Sendable {
    let originalPath: String
    let backupRelativePath: String
}

struct ModUpdateHistoryRecord: Identifiable, Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case installed
        case restored
    }

    let id: UUID
    let modUUID: String
    let modName: String
    let sourceArchiveName: String
    let previousVersion64: Int64
    let installedVersion64: Int64
    let previousSHA256: String
    let installedSHA256: String
    let installedAt: Date
    var status: Status
    var restoredAt: Date?
    let backupDirectoryName: String
    let backupItems: [ModUpdateBackupItem]
    /// Destinations introduced by the update that did not exist in the backed-up version.
    let createdPaths: [String]?
    let wasActive: Bool
    let previousUserPosition: Int?
    let nexusURL: String?
}

struct ModUpdateProvenance: Codable, Equatable, Sendable {
    let modUUID: String
    var installedPath: String
    var installedSHA256: String
    var installedVersion64: Int64
    var nexusURL: String?
    var nexusModID: Int?
    var selectedFileID: Int?
    var lastTransactionID: UUID
    var updatedAt: Date
}

struct ModUpdateHistoryPayload: Codable, Equatable {
    var records: [ModUpdateHistoryRecord]
    var provenanceByUUID: [String: ModUpdateProvenance]
}

struct ModUpdateAcquisitionCapability: Equatable, Sendable {
    let browserAndManualArchive: Bool
    let directNexusDownload: Bool
    let directDownloadReason: String

    static let current = ModUpdateAcquisitionCapability(
        browserAndManualArchive: true,
        directNexusDownload: false,
        directDownloadReason: "Direct downloads require registered-app authentication and an account/API capability that this build does not yet provide."
    )
}

struct ModUpdateProgress: Equatable, Sendable {
    enum Stage: String, Sendable {
        case idle = "Idle"
        case inspecting = "Inspecting archive"
        case backingUp = "Creating rollback backup"
        case committing = "Installing candidate"
        case verifying = "Verifying installation"
        case rollingBack = "Rolling back"
        case restoring = "Restoring previous version"
    }

    let stage: Stage
    let completed: Int
    let total: Int
}
