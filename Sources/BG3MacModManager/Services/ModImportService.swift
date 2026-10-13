// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

protocol ModImporting: Sendable {
    func importMods(from urls: [URL], to modsFolder: URL) -> ModImportService.Result
}

/// Performs import filesystem work away from the main actor.
struct ModImportService: ModImporting {
    let backupsDirectory: URL

    init(backupsDirectory: URL = FileLocations.appSupportDirectory.appendingPathComponent("ImportBackups")) {
        self.backupsDirectory = backupsDirectory
    }

    struct Result: Sendable {
        var importedCount = 0
        var importedFilenames: [String] = []
        var replacedFilenames: [String] = []
        var alreadyPresentFilenames: [String] = []
        var errors: [String] = []
    }

    func importMods(from urls: [URL], to modsFolder: URL) -> Result {
        var result = Result()
        do {
            try FileLocations.ensureDirectoryExists(modsFolder)
        } catch {
            result.errors.append(error.localizedDescription)
            return result
        }

        for url in urls {
            if Task.isCancelled {
                result.errors.append("Import cancelled")
                break
            }
            do {
                let ext = url.pathExtension.lowercased()
                if ext == "pak" {
                    let destination = modsFolder.appendingPathComponent(url.lastPathComponent)
                    _ = try PakReader.listFiles(at: url)
                    let sameFile = TransactionalFileService.identifiesSameFile(url, destination)
                    var replacements: [TransactionalFileService.Replacement] = [
                        .init(source: url, destination: destination),
                    ]
                    let companion = destination.deletingPathExtension().appendingPathExtension("json")
                    let sourceCompanion = url.deletingPathExtension().appendingPathExtension("json")
                    var removals: [URL] = []
                    if !sameFile {
                        if FileManager.default.fileExists(atPath: sourceCompanion.path) {
                            _ = try JSONSerialization.jsonObject(with: Data(contentsOf: sourceCompanion))
                            replacements.append(.init(source: sourceCompanion, destination: companion))
                        } else {
                            removals.append(companion)
                        }
                    }
                    let replacement = try install(replacements, removing: removals)
                    if replacement.changedDestinations.isEmpty {
                        result.alreadyPresentFilenames.append(url.lastPathComponent)
                    } else {
                        result.importedCount += 1
                        result.importedFilenames.append(url.lastPathComponent)
                        if replacement.replacedDestinations.contains(destination) {
                            result.replacedFilenames.append(url.lastPathComponent)
                        }
                    }
                } else if ArchiveService.ArchiveFormat(
                    pathExtension: ext,
                    fullFilename: url.lastPathComponent
                ) != nil {
                    let imported = try importArchive(url, to: modsFolder)
                    result.replacedFilenames.append(contentsOf: imported.replacedDestinations.filter { $0.pathExtension.lowercased() == "pak" }.map(\.lastPathComponent))
                    result.importedFilenames.append(contentsOf: imported.changedDestinations.filter { $0.pathExtension.lowercased() == "pak" }.map(\.lastPathComponent))
                    result.importedCount += 1
                } else {
                    throw ArchiveService.ArchiveError.unsupportedFormat(ext)
                }
            } catch {
                result.errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        return result
    }

    private func importArchive(_ archiveURL: URL, to modsFolder: URL) throws -> TransactionalFileService.Result {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try ArchiveService().extract(archive: archiveURL, to: tempDir)

        var pakFiles: [URL] = []
        var infoJsonFiles: [URL] = []
        let enumerator = FileManager.default.enumerator(
            at: tempDir,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let fileURL = enumerator?.nextObject() as? URL {
            guard try fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            if fileURL.pathExtension.lowercased() == "pak" {
                pakFiles.append(fileURL)
            } else if fileURL.pathExtension.lowercased() == "json" {
                infoJsonFiles.append(fileURL)
            }
        }
        pakFiles.sort { $0.path < $1.path }
        infoJsonFiles.sort { $0.path < $1.path }
        guard !pakFiles.isEmpty else {
            throw ArchiveService.ArchiveError.extractionFailed("No PAK files found")
        }

        var replacements: [TransactionalFileService.Replacement] = []
        var removals: [URL] = []
        for pakURL in pakFiles {
            _ = try PakReader.listFiles(at: pakURL)
            let baseName = pakURL.deletingPathExtension().lastPathComponent
            replacements.append(.init(
                source: pakURL,
                destination: modsFolder.appendingPathComponent(pakURL.lastPathComponent)
            ))
            if let infoJson = findNearestInfoJson(
                for: pakURL,
                in: infoJsonFiles,
                archiveRoot: tempDir
            ) {
                _ = try JSONSerialization.jsonObject(with: Data(contentsOf: infoJson))
                replacements.append(.init(
                    source: infoJson,
                    destination: modsFolder.appendingPathComponent("\(baseName).json")
                ))
            } else {
                removals.append(modsFolder.appendingPathComponent("\(baseName).json"))
            }
        }
        removals.append(modsFolder.appendingPathComponent("info.json"))
        return try install(replacements, removing: removals)
    }

    private func install(
        _ replacements: [TransactionalFileService.Replacement], removing removals: [URL]
    ) throws -> TransactionalFileService.Result {
        let originals = replacements.filter {
            !TransactionalFileService.identifiesSameFile($0.source, $0.destination)
        }.map(\.destination) + removals
        let existing = Set(originals.filter { FileManager.default.fileExists(atPath: $0.path) })
        let backup = backupsDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        do {
            if !existing.isEmpty {
                try FileManager.default.createDirectory(at: backup, withIntermediateDirectories: true)
                for original in existing {
                    try FileManager.default.copyItem(at: original, to: backup.appendingPathComponent(original.lastPathComponent))
                }
            }
            return try TransactionalFileService.replaceFiles(replacements, removing: removals)
        } catch {
            // Retain the originals if automatic rollback failed; otherwise this attempt changed nothing.
            if case TransactionalFileService.TransactionError.rollbackFailed = error { throw error }
            try? FileManager.default.removeItem(at: backup)
            throw error
        }
    }

    private func findNearestInfoJson(
        for pakURL: URL,
        in infoJsonFiles: [URL],
        archiveRoot: URL
    ) -> URL? {
        var searchDirectory = pakURL.deletingLastPathComponent()
        let root = archiveRoot.standardizedFileURL.resolvingSymlinksInPath()
        while searchDirectory.standardizedFileURL.path.hasPrefix(root.path) {
            let siblings = infoJsonFiles.filter {
                $0.deletingLastPathComponent().standardizedFileURL == searchDirectory.standardizedFileURL
            }
            let named = pakURL.deletingPathExtension().lastPathComponent + ".json"
            if let match = siblings.first(where: { $0.lastPathComponent.caseInsensitiveCompare(named) == .orderedSame }) {
                return match
            }
            if let match = siblings.first(where: { $0.lastPathComponent.caseInsensitiveCompare("info.json") == .orderedSame }) {
                return match
            }
            let parent = searchDirectory.deletingLastPathComponent()
            if parent.standardizedFileURL == searchDirectory.standardizedFileURL { break }
            searchDirectory = parent
        }
        return nil
    }
}
