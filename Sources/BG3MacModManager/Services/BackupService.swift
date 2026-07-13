// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Darwin

/// Manages backups of modsettings.lsx before making changes.
final class BackupService {

    private let modSettingsURL: URL
    private let backupsDirectory: URL

    init(
        modSettingsURL: URL = FileLocations.modSettingsFile,
        backupsDirectory: URL = FileLocations.backupsDirectory
    ) {
        self.modSettingsURL = modSettingsURL
        self.backupsDirectory = backupsDirectory
    }

    struct Backup: Identifiable, Sendable {
        let id: String
        let url: URL
        let date: Date
        let fileSize: Int

        var displayName: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return "Backup - \(formatter.string(from: date))"
        }
    }

    // MARK: - Create Backup

    /// Create a timestamped backup of modsettings.lsx before any modifications.
    @discardableResult
    func backupModSettings() throws -> Backup {
        let source = modSettingsURL
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw BackupError.sourceNotFound
        }

        try FileLocations.ensureDirectoryExists(backupsDirectory)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "modsettings-\(timestamp).lsx"
        let destination = backupsDirectory.appendingPathComponent(filename)

        try FileManager.default.copyItem(at: source, to: destination)

        let attrs = try FileManager.default.attributesOfItem(atPath: destination.path)
        let size = (attrs[.size] as? Int) ?? 0

        return Backup(id: filename, url: destination, date: Date(), fileSize: size)
    }

    // MARK: - List Backups

    /// List all available backups, newest first.
    func listBackups() throws -> [Backup] {
        let dir = backupsDirectory
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }

        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
        let lsxFiles = files.filter { $0.pathExtension == "lsx" }

        return lsxFiles.compactMap { url -> Backup? in
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                  let date = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? Int else {
                return nil
            }
            return Backup(id: url.lastPathComponent, url: url, date: date, fileSize: size)
        }.sorted { $0.date > $1.date }
    }

    // MARK: - Restore

    /// Restore modsettings.lsx from a backup.
    func restore(backup: Backup) throws {
        let destination = modSettingsURL
        let destinationExisted = FileManager.default.fileExists(atPath: destination.path)
        let wasLocked = destinationExisted && isModSettingsLocked()

        // Unlock the file if it's locked (macOS file locking)
        if wasLocked && !setImmutable(false, at: destination) {
            throw BackupError.unlockFailed
        }
        defer {
            if wasLocked {
                _ = setImmutable(true, at: destination)
            }
        }

        // A safety backup is mandatory before replacing the live file.
        if destinationExisted {
            try FileLocations.ensureDirectoryExists(backupsDirectory)
            let safetyBackup = backupsDirectory.appendingPathComponent(
                "pre-restore-\(UUID().uuidString).lsx"
            )
            try FileManager.default.copyItem(at: destination, to: safetyBackup)
        }

        try TransactionalFileService.replaceFiles([
            .init(source: backup.url, destination: destination),
        ])
    }

    // MARK: - Delete

    /// Delete a specific backup.
    func delete(backup: Backup) throws {
        try FileManager.default.removeItem(at: backup.url)
    }

    /// Delete all backups older than the given number of days.
    func pruneBackups(olderThanDays days: Int = 30) throws {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let backups = try listBackups()

        for backup in backups where backup.date < cutoff {
            try? FileManager.default.removeItem(at: backup.url)
        }
    }

    // MARK: - File Locking

    /// Lock modsettings.lsx to prevent the game from overwriting it.
    @discardableResult
    func lockModSettings() -> Bool {
        return setImmutable(true, at: modSettingsURL)
    }

    /// Unlock modsettings.lsx so it can be modified.
    @discardableResult
    func unlockModSettings() -> Bool {
        return setImmutable(false, at: modSettingsURL)
    }

    /// Returns true if modsettings.lsx is currently locked.
    func isModSettingsLocked() -> Bool {
        let path = modSettingsURL.path
        var statBuf = stat()
        guard stat(path, &statBuf) == 0 else { return false }
        return (statBuf.st_flags & UInt32(UF_IMMUTABLE)) != 0
    }

    private func setImmutable(_ immutable: Bool, at url: URL) -> Bool {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else { return false }

        // Get current flags
        var statBuf = stat()
        guard stat(path, &statBuf) == 0 else { return false }

        // Set or clear the user immutable flag
        var newFlags = statBuf.st_flags
        if immutable {
            newFlags |= UInt32(UF_IMMUTABLE)
        } else {
            newFlags &= ~UInt32(UF_IMMUTABLE)
        }

        let result = Darwin.chflags(path, newFlags)
        return result == 0
    }

    // MARK: - Errors

    enum BackupError: Error, LocalizedError {
        case sourceNotFound
        case unlockFailed

        var errorDescription: String? {
            switch self {
            case .sourceNotFound: return "modsettings.lsx not found - nothing to back up"
            case .unlockFailed: return "Could not unlock modsettings.lsx for restore"
            }
        }
    }
}
