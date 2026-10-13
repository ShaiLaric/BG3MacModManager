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
        let filename = "modsettings-\(timestamp)-\(UUID().uuidString).lsx"
        let destination = backupsDirectory.appendingPathComponent(filename)

        try copyBackup(from: source, to: destination)

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
                  let modified = attrs[.modificationDate] as? Date,
                  let size = attrs[.size] as? Int else {
                return nil
            }
            return Backup(id: url.lastPathComponent, url: url, date: backupDate(from: url) ?? modified, fileSize: size)
        }.sorted { $0.date > $1.date }
    }

    // MARK: - Restore

    /// Restore modsettings.lsx from a backup.
    func restore(backup: Backup, finalize: () throws -> Void = {}) throws {
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
            try copyBackup(from: destination, to: safetyBackup)
        }

        // A legacy backup may still be immutable. Restore from an unlocked temporary
        // copy so its flags cannot lock the live file before verification/persistence.
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".lsx")
        defer { try? FileManager.default.removeItem(at: staged) }
        try copyBackup(from: backup.url, to: staged)
        try TransactionalFileService.replaceFiles([
            .init(source: staged, destination: destination),
        ], finalize: finalize)
    }

    // MARK: - Delete

    /// Delete a specific backup.
    func delete(backup: Backup) throws {
        try unlockBackup(at: backup.url)
        try FileManager.default.removeItem(at: backup.url)
    }

    /// Delete all backups older than the given number of days.
    func pruneBackups(olderThanDays days: Int = 30) throws {
        guard days > 0 else { return }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let backups = try listBackups()

        for backup in backups where backup.date < cutoff {
            try delete(backup: backup)
        }
    }

    private func copyBackup(from source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
        // copyItem preserves the live file's lock. Only the backup should be unlocked.
        try unlockBackup(at: destination)
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: destination.path)
    }

    /// Old copies inherited the live file's mtime; their filename records the backup time.
    private func backupDate(from url: URL) -> Date? {
        let name = url.deletingPathExtension().lastPathComponent
        guard name.hasPrefix("modsettings-"), name.count >= 32 else { return nil }
        let stamp = String(name.dropFirst(12).prefix(20))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.date(from: stamp.uppercased())
    }

    private func unlockBackup(at url: URL) throws {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSFilePathErrorKey: url.path,
            ])
        }
        guard info.st_flags & UInt32(UF_IMMUTABLE) != 0 else { return }

        // Preserve other flags and never follow a backup symlink to the live file.
        guard lchflags(url.path, info.st_flags & ~UInt32(UF_IMMUTABLE)) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [
                NSFilePathErrorKey: url.path,
            ])
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
