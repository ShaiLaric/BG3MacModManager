// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Stages file replacements beside their destinations and rolls back a batch if any commit fails.
enum TransactionalFileService {
    struct Replacement {
        let source: URL
        let destination: URL
    }

    struct Result {
        let changedDestinations: [URL]
        let replacedDestinations: [URL]
    }

    enum TransactionError: Error, LocalizedError {
        case duplicateDestination(String)
        case sourceIsNotARegularFile(String)
        case stagedCopyMismatch(String)
        case rollbackFailed([String])

        var errorDescription: String? {
            switch self {
            case .duplicateDestination(let path):
                return "More than one file was mapped to the same destination: \(path)"
            case .sourceIsNotARegularFile(let path):
                return "Replacement source is not a regular file: \(path)"
            case .stagedCopyMismatch(let path):
                return "The staged replacement did not match its source: \(path)"
            case .rollbackFailed(let paths):
                return "A file replacement failed and automatic rollback was incomplete. Recovery copies were preserved at: \(paths.joined(separator: ", "))"
            }
        }
    }

    /// Returns true when two URLs identify the same physical filesystem item.
    static func identifiesSameFile(_ lhs: URL, _ rhs: URL) -> Bool {
        let left = lhs.standardizedFileURL.resolvingSymlinksInPath()
        let right = rhs.standardizedFileURL.resolvingSymlinksInPath()
        if left == right { return true }

        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey]
        guard let leftID = try? left.resourceValues(forKeys: keys).fileResourceIdentifier,
              let rightID = try? right.resourceValues(forKeys: keys).fileResourceIdentifier,
              let leftHashable = leftID as? AnyHashable,
              let rightHashable = rightID as? AnyHashable else {
            return false
        }
        return leftHashable == rightHashable
    }

    /// Atomically replaces one or more files. All sources are staged before any destination changes.
    /// If a later replacement fails, earlier replacements are restored from sibling rollback copies.
    @discardableResult
    static func replaceFiles(
        _ replacements: [Replacement],
        removing removals: [URL] = [],
        fileManager: FileManager = .default,
        finalize: () throws -> Void = {}
    ) throws -> Result {
        let actionable = replacements.filter {
            !identifiesSameFile($0.source, $0.destination)
        }
        guard !actionable.isEmpty || !removals.isEmpty else {
            try finalize()
            return Result(changedDestinations: [], replacedDestinations: [])
        }

        var destinationPaths = Set<String>()
        for destination in actionable.map(\.destination) + removals {
            let path = destination.standardizedFileURL.path
            guard destinationPaths.insert(path).inserted else {
                throw TransactionError.duplicateDestination(path)
            }
        }

        struct StagedReplacement {
            let destination: URL
            let staged: URL?
            let rollback: URL?
            let destinationExisted: Bool
        }

        var stagedReplacements: [StagedReplacement] = []
        var temporaryFiles: [URL] = []
        var committedCount = 0
        var rollbackCopiesToPreserve = Set<URL>()

        func temporarySibling(of destination: URL, role: String) -> URL {
            destination.deletingLastPathComponent().appendingPathComponent(
                ".\(destination.lastPathComponent).\(role)-\(UUID().uuidString)"
            )
        }

        defer {
            for url in temporaryFiles where !rollbackCopiesToPreserve.contains(url) {
                try? fileManager.removeItem(at: url)
            }
        }

        // Stage and validate every source before changing any destination.
        for replacement in actionable {
            let sourceValues = try replacement.source.resourceValues(forKeys: [
                .isRegularFileKey, .fileSizeKey,
            ])
            guard sourceValues.isRegularFile == true else {
                throw TransactionError.sourceIsNotARegularFile(replacement.source.path)
            }

            let parent = replacement.destination.deletingLastPathComponent()
            try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)

            let staged = temporarySibling(of: replacement.destination, role: "staged")
            temporaryFiles.append(staged)
            try fileManager.copyItem(at: replacement.source, to: staged)

            let stagedValues = try staged.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard stagedValues.isRegularFile == true,
                  stagedValues.fileSize == sourceValues.fileSize else {
                throw TransactionError.stagedCopyMismatch(replacement.source.path)
            }

            let destinationExisted = fileManager.fileExists(atPath: replacement.destination.path)
            let rollback: URL?
            if destinationExisted {
                let rollbackURL = temporarySibling(of: replacement.destination, role: "rollback")
                temporaryFiles.append(rollbackURL)
                try fileManager.copyItem(at: replacement.destination, to: rollbackURL)
                rollback = rollbackURL
            } else {
                rollback = nil
            }

            stagedReplacements.append(StagedReplacement(
                destination: replacement.destination,
                staged: staged,
                rollback: rollback,
                destinationExisted: destinationExisted
            ))
        }

        for destination in removals where fileManager.fileExists(atPath: destination.path) {
            let rollback = temporarySibling(of: destination, role: "rollback")
            temporaryFiles.append(rollback)
            try fileManager.copyItem(at: destination, to: rollback)
            stagedReplacements.append(StagedReplacement(
                destination: destination, staged: nil, rollback: rollback, destinationExisted: true
            ))
        }

        do {
            for item in stagedReplacements {
                if item.staged == nil {
                    try fileManager.removeItem(at: item.destination)
                } else if item.destinationExisted {
                    _ = try fileManager.replaceItemAt(
                        item.destination,
                        withItemAt: item.staged!,
                        backupItemName: nil,
                        options: []
                    )
                } else {
                    try fileManager.moveItem(at: item.staged!, to: item.destination)
                }
                committedCount += 1
            }
            // Verification and persistence participate in the same rollback boundary.
            try finalize()
        } catch {
            // Roll back only the destinations that were already committed, in reverse order.
            for item in stagedReplacements.prefix(committedCount).reversed() {
                if let rollback = item.rollback {
                    do {
                        if fileManager.fileExists(atPath: item.destination.path) {
                            _ = try fileManager.replaceItemAt(
                                item.destination,
                                withItemAt: rollback,
                                backupItemName: nil,
                                options: []
                            )
                        } else {
                            try fileManager.moveItem(at: rollback, to: item.destination)
                        }
                    } catch {
                        // Preserve the rollback copy for manual recovery when automatic rollback fails.
                        rollbackCopiesToPreserve.insert(rollback)
                    }
                } else {
                    do {
                        try fileManager.removeItem(at: item.destination)
                    } catch {
                        // A failed removal leaves the new file visible; report incomplete rollback.
                        rollbackCopiesToPreserve.insert(item.destination)
                    }
                }
            }
            if !rollbackCopiesToPreserve.isEmpty {
                throw TransactionError.rollbackFailed(
                    rollbackCopiesToPreserve.map(\.path).sorted()
                )
            }
            throw error
        }

        return Result(
            changedDestinations: stagedReplacements.map(\.destination),
            replacedDestinations: stagedReplacements.compactMap {
                $0.destinationExisted ? $0.destination : nil
            }
        )
    }
}
