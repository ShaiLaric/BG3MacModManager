// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Performs import filesystem work away from the main actor.
struct ModImportService: Sendable {
    struct Result: Sendable {
        var importedCount = 0
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
                    let replacement = try TransactionalFileService.replaceFiles([
                        .init(source: url, destination: destination),
                    ])
                    if replacement.changedDestinations.isEmpty {
                        result.alreadyPresentFilenames.append(url.lastPathComponent)
                    } else {
                        result.importedCount += 1
                        if replacement.replacedDestinations.contains(destination) {
                            result.replacedFilenames.append(url.lastPathComponent)
                        }
                    }
                } else if ArchiveService.ArchiveFormat(
                    pathExtension: ext,
                    fullFilename: url.lastPathComponent
                ) != nil {
                    let replaced = try importArchive(url, to: modsFolder)
                    result.replacedFilenames.append(contentsOf: replaced)
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

    private func importArchive(_ archiveURL: URL, to modsFolder: URL) throws -> [String] {
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
            if fileURL.pathExtension.lowercased() == "pak" {
                pakFiles.append(fileURL)
            } else if fileURL.lastPathComponent.lowercased() == "info.json" {
                infoJsonFiles.append(fileURL)
            }
        }
        guard !pakFiles.isEmpty else {
            throw ArchiveService.ArchiveError.extractionFailed("No PAK files found")
        }

        var replacements: [TransactionalFileService.Replacement] = []
        for pakURL in pakFiles {
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
                replacements.append(.init(
                    source: infoJson,
                    destination: modsFolder.appendingPathComponent("\(baseName).json")
                ))
            }
        }

        let result = try TransactionalFileService.replaceFiles(replacements)
        let staleInfoJson = modsFolder.appendingPathComponent("info.json")
        try? FileManager.default.removeItem(at: staleInfoJson)
        return result.replacedDestinations
            .filter { $0.pathExtension.lowercased() == "pak" }
            .map(\.lastPathComponent)
    }

    private func findNearestInfoJson(
        for pakURL: URL,
        in infoJsonFiles: [URL],
        archiveRoot: URL
    ) -> URL? {
        var searchDirectory = pakURL.deletingLastPathComponent()
        let root = archiveRoot.standardizedFileURL.resolvingSymlinksInPath()
        while searchDirectory.standardizedFileURL.path.hasPrefix(root.path) {
            if let match = infoJsonFiles.first(where: {
                $0.deletingLastPathComponent().standardizedFileURL ==
                    searchDirectory.standardizedFileURL
            }) {
                return match
            }
            let parent = searchDirectory.deletingLastPathComponent()
            if parent.standardizedFileURL == searchDirectory.standardizedFileURL { break }
            searchDirectory = parent
        }
        return nil
    }
}
