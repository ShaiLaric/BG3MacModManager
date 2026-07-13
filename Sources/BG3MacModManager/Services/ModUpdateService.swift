// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

actor ModUpdateService {
    enum UpdateError: Error, LocalizedError {
        case targetHasNoInstalledPAK
        case unsupportedArchive(String)
        case noPAK
        case multiplePAKs([String])
        case metadataRequired
        case UUIDMismatch(expected: String, found: String)
        case candidateCouldNotBeDiscovered
        case verificationFailed(String)
        case rollbackFailed(String)
        case backupMissing(String)
        case unsafeHistory(String)
        case operationInProgress
        case installedChangedSinceInspection
        case candidateChangedSinceInspection
        case historyRecordMissing
        case historyRecordAlreadyRestored
        case installedChangedSinceUpdate

        var errorDescription: String? {
            switch self {
            case .targetHasNoInstalledPAK:
                return "This mod has no installed PAK to replace. Use Import for a new installation."
            case .unsupportedArchive(let ext):
                return "Unsupported update archive format: \(ext)"
            case .noPAK:
                return "The selected update contains no PAK file."
            case .multiplePAKs(let names):
                return "The update contains multiple PAK files (\(names.joined(separator: ", "))). Multi-PAK updates require an explicit file mapping and are not installed automatically."
            case .metadataRequired:
                return "The candidate PAK has no readable UUID metadata, so it cannot be safely matched to the installed mod."
            case .UUIDMismatch(let expected, let found):
                return "The candidate UUID \(found) does not match the installed mod UUID \(expected)."
            case .candidateCouldNotBeDiscovered:
                return "The staged candidate could not be read after extraction."
            case .verificationFailed(let detail):
                return "The installed update failed verification and was rolled back: \(detail)"
            case .rollbackFailed(let detail):
                return "The update failed and rollback was incomplete: \(detail)"
            case .backupMissing(let path):
                return "The rollback backup is missing: \(path)"
            case .unsafeHistory(let detail):
                return "The update record contains an unsafe file path: \(detail)"
            case .operationInProgress:
                return "Another Mods-folder mutation is already in progress."
            case .installedChangedSinceInspection:
                return "The installed PAK changed after the update plan was reviewed. Inspect the archive again."
            case .candidateChangedSinceInspection:
                return "The staged candidate changed after the update plan was reviewed. Inspect the archive again."
            case .historyRecordMissing:
                return "The update history record no longer exists. Refresh Update History before restoring."
            case .historyRecordAlreadyRestored:
                return "This update has already been restored."
            case .installedChangedSinceUpdate:
                return "The installed PAK changed after this update. Restore was cancelled to avoid overwriting a newer file."
            }
        }
    }

    private let modsFolder: URL
    private let backupsDirectory: URL
    private let historyService: ModUpdateHistoryService
    private let fileManager: FileManager
    private var mutationInProgress = false

    init(
        modsFolder: URL = FileLocations.modsFolder,
        backupsDirectory: URL = FileLocations.modUpdateBackupsDirectory,
        historyURL: URL = FileLocations.modUpdateHistoryFile,
        fileManager: FileManager = .default
    ) {
        self.modsFolder = modsFolder
        self.backupsDirectory = backupsDirectory
        historyService = ModUpdateHistoryService(url: historyURL)
        self.fileManager = fileManager
    }

    func inspect(
        sourceURL: URL,
        target: ModInfo,
        wasActive: Bool,
        previousUserPosition: Int?,
        nexusURL: String?
    ) throws -> ModUpdatePlan {
        guard let installedPAK = target.pakFilePath,
              fileManager.fileExists(atPath: installedPAK.path) else {
            throw UpdateError.targetHasNoInstalledPAK
        }
        guard isDirectChildOfModsFolder(installedPAK) else {
            throw UpdateError.unsafeHistory(installedPAK.path)
        }
        try Task.checkCancellation()

        let staging = fileManager.temporaryDirectory
            .appendingPathComponent("BG3MM-ModUpdate-\(UUID().uuidString)", isDirectory: true)
        let extracted = staging.appendingPathComponent("extracted", isDirectory: true)
        let candidateDirectory = staging.appendingPathComponent("candidate", isDirectory: true)
        try fileManager.createDirectory(at: extracted, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: candidateDirectory, withIntermediateDirectories: true)

        do {
            let pakFiles: [URL]
            if sourceURL.pathExtension.caseInsensitiveCompare("pak") == .orderedSame {
                pakFiles = [sourceURL]
            } else if ArchiveService.ArchiveFormat(
                pathExtension: sourceURL.pathExtension,
                fullFilename: sourceURL.lastPathComponent
            ) != nil {
                try ArchiveService().extract(archive: sourceURL, to: extracted)
                pakFiles = try regularFiles(in: extracted).filter {
                    $0.pathExtension.caseInsensitiveCompare("pak") == .orderedSame
                }
            } else {
                throw UpdateError.unsupportedArchive(sourceURL.pathExtension)
            }

            guard !pakFiles.isEmpty else { throw UpdateError.noPAK }
            guard pakFiles.count == 1 else {
                throw UpdateError.multiplePAKs(pakFiles.map(\.lastPathComponent).sorted())
            }

            let sourcePAK = pakFiles[0]
            let candidatePAK = candidateDirectory.appendingPathComponent(sourcePAK.lastPathComponent)
            try fileManager.copyItem(at: sourcePAK, to: candidatePAK)

            let infoJSON = try nearestInfoJSON(for: sourcePAK, within: extracted, sourceIsPAK: sourceURL == sourcePAK)
            let stagedInfoJSON: URL?
            if let infoJSON {
                let destination = candidateDirectory.appendingPathComponent(
                    candidatePAK.deletingPathExtension().lastPathComponent + ".json"
                )
                try fileManager.copyItem(at: infoJSON, to: destination)
                stagedInfoJSON = destination
            } else {
                stagedInfoJSON = nil
            }

            let discovered = try ModDiscoveryService(
                modsFolder: candidateDirectory,
                modSettingsURL: candidateDirectory.appendingPathComponent("no-modsettings.lsx")
            ).discoverMods()
            guard let candidate = discovered.first(where: {
                $0.pakFilePath?.standardizedFileURL == candidatePAK.standardizedFileURL
            }) else {
                throw UpdateError.candidateCouldNotBeDiscovered
            }
            guard candidate.metadataSource != .filename else { throw UpdateError.metadataRequired }

            let expectedUUID = ModIdentity.comparisonKey(target.uuid)
            let candidateUUID = ModIdentity.comparisonKey(candidate.uuid)
            guard expectedUUID == candidateUUID else {
                throw UpdateError.UUIDMismatch(expected: expectedUUID, found: candidateUUID)
            }
            _ = try PakReader.listFiles(at: candidatePAK)

            return ModUpdatePlan(
                id: UUID(),
                targetUUID: expectedUUID,
                targetName: target.name,
                installedPAK: installedPAK,
                candidatePAK: candidatePAK,
                candidateInfoJSON: stagedInfoJSON,
                stagingDirectory: staging,
                sourceArchiveName: sourceURL.lastPathComponent,
                installedVersion64: target.version64,
                candidateVersion64: candidate.version64,
                installedSHA256: try sha256(of: installedPAK),
                candidateSHA256: try sha256(of: candidatePAK),
                wasActive: wasActive,
                previousUserPosition: previousUserPosition,
                nexusURL: nexusURL
            )
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    func execute(
        _ plan: ModUpdatePlan,
        progress: @Sendable (ModUpdateProgress) async -> Void
    ) async throws -> ModUpdateHistoryRecord {
        guard !mutationInProgress else { throw UpdateError.operationInProgress }
        mutationInProgress = true
        defer { mutationInProgress = false }
        defer { try? fileManager.removeItem(at: plan.stagingDirectory) }
        try Task.checkCancellation()
        guard try sha256(of: plan.installedPAK) == plan.installedSHA256 else {
            throw UpdateError.installedChangedSinceInspection
        }
        guard try sha256(of: plan.candidatePAK) == plan.candidateSHA256 else {
            throw UpdateError.candidateChangedSinceInspection
        }
        var payload = try historyService.load()
        await progress(.init(stage: .backingUp, completed: 1, total: 4))

        let transactionID = UUID()
        let backupDirectory = backupsDirectory.appendingPathComponent(
            transactionID.uuidString,
            isDirectory: true
        )
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)

        let installedJSON = companionJSON(for: plan.installedPAK)
        var originalURLs = [plan.installedPAK]
        if fileManager.fileExists(atPath: installedJSON.path) { originalURLs.append(installedJSON) }
        var backupItems: [ModUpdateBackupItem] = []
        for original in originalURLs {
            let backup = backupDirectory.appendingPathComponent(original.lastPathComponent)
            try fileManager.copyItem(at: original, to: backup)
            backupItems.append(.init(
                originalPath: original.path,
                backupRelativePath: backup.lastPathComponent
            ))
        }

        var createdDestinations: [URL] = []
        do {
            try Task.checkCancellation()
            await progress(.init(stage: .committing, completed: 2, total: 4))
            var replacements: [TransactionalFileService.Replacement] = [
                .init(source: plan.candidatePAK, destination: plan.installedPAK),
            ]
            if let candidateInfoJSON = plan.candidateInfoJSON {
                if !fileManager.fileExists(atPath: installedJSON.path) {
                    createdDestinations.append(installedJSON)
                }
                replacements.append(.init(source: candidateInfoJSON, destination: installedJSON))
            }
            try TransactionalFileService.replaceFiles(replacements, fileManager: fileManager)
            if plan.candidateInfoJSON == nil, fileManager.fileExists(atPath: installedJSON.path) {
                try fileManager.removeItem(at: installedJSON)
            }

            await progress(.init(stage: .verifying, completed: 3, total: 4))
            try verifyInstalled(plan: plan)

            let installedAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
            let record = ModUpdateHistoryRecord(
                id: transactionID,
                modUUID: plan.targetUUID,
                modName: plan.targetName,
                sourceArchiveName: plan.sourceArchiveName,
                previousVersion64: plan.installedVersion64,
                installedVersion64: plan.candidateVersion64,
                previousSHA256: plan.installedSHA256,
                installedSHA256: try sha256(of: plan.installedPAK),
                installedAt: installedAt,
                status: .installed,
                restoredAt: nil,
                backupDirectoryName: transactionID.uuidString,
                backupItems: backupItems,
                createdPaths: createdDestinations.map(\.path),
                wasActive: plan.wasActive,
                previousUserPosition: plan.previousUserPosition,
                nexusURL: plan.nexusURL
            )
            payload.records.insert(record, at: 0)
            payload.provenanceByUUID[plan.targetUUID] = ModUpdateProvenance(
                modUUID: plan.targetUUID,
                installedPath: plan.installedPAK.path,
                installedSHA256: record.installedSHA256,
                installedVersion64: plan.candidateVersion64,
                nexusURL: plan.nexusURL,
                nexusModID: plan.nexusURL.flatMap(extractNexusModID),
                selectedFileID: nil,
                lastTransactionID: transactionID,
                updatedAt: installedAt
            )
            try historyService.save(payload)
            await progress(.init(stage: .idle, completed: 4, total: 4))
            return record
        } catch {
            await progress(.init(stage: .rollingBack, completed: 3, total: 4))
            do {
                try restoreBackupItems(
                    backupItems,
                    backupDirectory: backupDirectory,
                    createdDestinations: createdDestinations
                )
            } catch {
                throw UpdateError.rollbackFailed(error.localizedDescription)
            }
            throw UpdateError.verificationFailed(error.localizedDescription)
        }
    }

    func discard(_ plan: ModUpdatePlan) {
        try? fileManager.removeItem(at: plan.stagingDirectory)
    }

    func restore(
        _ record: ModUpdateHistoryRecord,
        progress: @Sendable (ModUpdateProgress) async -> Void
    ) async throws -> ModUpdateHistoryRecord {
        guard !mutationInProgress else { throw UpdateError.operationInProgress }
        mutationInProgress = true
        defer { mutationInProgress = false }
        var payload = try historyService.load()
        guard let historyIndex = payload.records.firstIndex(where: { $0.id == record.id }) else {
            throw UpdateError.historyRecordMissing
        }
        let persistedRecord = payload.records[historyIndex]
        guard persistedRecord.status == .installed else {
            throw UpdateError.historyRecordAlreadyRestored
        }
        guard UUID(uuidString: persistedRecord.backupDirectoryName) != nil else {
            throw UpdateError.unsafeHistory(persistedRecord.backupDirectoryName)
        }
        let backupDirectory = backupsDirectory.appendingPathComponent(persistedRecord.backupDirectoryName)
        for item in persistedRecord.backupItems {
            guard isDirectChildOfModsFolder(URL(fileURLWithPath: item.originalPath)),
                  item.backupRelativePath == URL(fileURLWithPath: item.backupRelativePath).lastPathComponent,
                  !item.backupRelativePath.contains("\\") else {
                throw UpdateError.unsafeHistory(item.originalPath)
            }
            let backup = backupDirectory.appendingPathComponent(item.backupRelativePath)
            guard fileManager.fileExists(atPath: backup.path) else {
                throw UpdateError.backupMissing(backup.path)
            }
        }
        let createdURLs = try (persistedRecord.createdPaths ?? []).map { path -> URL in
            let url = URL(fileURLWithPath: path)
            guard isDirectChildOfModsFolder(url) else {
                throw UpdateError.unsafeHistory(path)
            }
            return url
        }

        await progress(.init(stage: .restoring, completed: 1, total: 2))
        let installedPAK = persistedRecord.backupItems
            .map { URL(fileURLWithPath: $0.originalPath) }
            .first { $0.pathExtension.caseInsensitiveCompare("pak") == .orderedSame }
        guard let installedPAK,
              fileManager.fileExists(atPath: installedPAK.path),
              try sha256(of: installedPAK) == persistedRecord.installedSHA256 else {
            throw UpdateError.installedChangedSinceUpdate
        }

        try TransactionalFileService.replaceFiles(persistedRecord.backupItems.map {
            .init(
                source: backupDirectory.appendingPathComponent($0.backupRelativePath),
                destination: URL(fileURLWithPath: $0.originalPath)
            )
        }, fileManager: fileManager)
        for url in createdURLs {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        _ = try PakReader.listFiles(at: installedPAK)

        payload.records[historyIndex].status = .restored
        let restoredAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        payload.records[historyIndex].restoredAt = restoredAt
        if var provenance = payload.provenanceByUUID[persistedRecord.modUUID] {
            provenance.installedPath = installedPAK.path
            provenance.installedSHA256 = try sha256(of: installedPAK)
            provenance.installedVersion64 = persistedRecord.previousVersion64
            provenance.updatedAt = restoredAt
            payload.provenanceByUUID[persistedRecord.modUUID] = provenance
        }
        try historyService.save(payload)
        await progress(.init(stage: .idle, completed: 2, total: 2))
        return payload.records[historyIndex]
    }

    private func verifyInstalled(plan: ModUpdatePlan) throws {
        _ = try PakReader.listFiles(at: plan.installedPAK)
        let discovered = try ModDiscoveryService(
            modsFolder: modsFolder,
            modSettingsURL: modsFolder.appendingPathComponent("no-modsettings.lsx")
        ).discoverMods()
        guard let installed = discovered.first(where: {
            $0.pakFilePath?.standardizedFileURL == plan.installedPAK.standardizedFileURL
        }), ModIdentity.comparisonKey(installed.uuid) == plan.targetUUID else {
            throw UpdateError.verificationFailed("The committed PAK did not rediscover with the expected UUID.")
        }
    }

    private func restoreBackupItems(
        _ items: [ModUpdateBackupItem],
        backupDirectory: URL,
        createdDestinations: [URL]
    ) throws {
        try TransactionalFileService.replaceFiles(items.map {
            .init(
                source: backupDirectory.appendingPathComponent($0.backupRelativePath),
                destination: URL(fileURLWithPath: $0.originalPath)
            )
        }, fileManager: fileManager)
        for url in createdDestinations where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func regularFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                files.append(url)
            }
        }
        return files
    }

    private func nearestInfoJSON(
        for pakURL: URL,
        within archiveRoot: URL,
        sourceIsPAK: Bool
    ) throws -> URL? {
        guard !sourceIsPAK else {
            let sibling = pakURL.deletingPathExtension().appendingPathExtension("json")
            return fileManager.fileExists(atPath: sibling.path) ? sibling : nil
        }
        let infoFiles = try regularFiles(in: archiveRoot).filter {
            $0.lastPathComponent.caseInsensitiveCompare("info.json") == .orderedSame
                || $0.lastPathComponent.caseInsensitiveCompare(
                    pakURL.deletingPathExtension().lastPathComponent + ".json"
                ) == .orderedSame
        }
        var directory = pakURL.deletingLastPathComponent()
        let rootPath = archiveRoot.standardizedFileURL.path
        while directory.standardizedFileURL.path.hasPrefix(rootPath) {
            if let named = infoFiles.first(where: {
                $0.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
                    && $0.lastPathComponent.caseInsensitiveCompare(
                        pakURL.deletingPathExtension().lastPathComponent + ".json"
                    ) == .orderedSame
            }) { return named }
            if let generic = infoFiles.first(where: {
                $0.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
            }) { return generic }
            let parent = directory.deletingLastPathComponent()
            if parent == directory { break }
            directory = parent
        }
        return nil
    }

    private func companionJSON(for pak: URL) -> URL {
        pak.deletingPathExtension().appendingPathExtension("json")
    }

    private func isDirectChildOfModsFolder(_ url: URL) -> Bool {
        url.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()
            == modsFolder.standardizedFileURL.resolvingSymlinksInPath()
    }

    private func extractNexusModID(_ value: String) -> Int? {
        guard let range = value.range(of: #"/mods/(\d+)"#, options: .regularExpression),
              let number = value[range].split(separator: "/").last else { return nil }
        return Int(number)
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1_048_576) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
