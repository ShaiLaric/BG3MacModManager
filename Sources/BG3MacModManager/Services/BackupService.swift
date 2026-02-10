import Foundation

/// Manages backups of modsettings.lsx before making changes.
final class BackupService {

    struct Backup: Identifiable {
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
        let source = FileLocations.modSettingsFile
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw BackupError.sourceNotFound
        }

        try FileLocations.ensureDirectoryExists(FileLocations.backupsDirectory)

        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "modsettings-\(timestamp).lsx"
        let destination = FileLocations.backupsDirectory.appendingPathComponent(filename)

        try FileManager.default.copyItem(at: source, to: destination)

        let attrs = try FileManager.default.attributesOfItem(atPath: destination.path)
        let size = (attrs[.size] as? Int) ?? 0

        return Backup(id: filename, url: destination, date: Date(), fileSize: size)
    }

    // MARK: - List Backups

    /// List all available backups, newest first.
    func listBackups() throws -> [Backup] {
        let dir = FileLocations.backupsDirectory
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
        let destination = FileLocations.modSettingsFile

        // Unlock the file if it's locked (macOS file locking)
        unlockFile(at: destination)

        // Create a safety backup before restoring
        if FileManager.default.fileExists(atPath: destination.path) {
            let safetyBackup = FileLocations.backupsDirectory.appendingPathComponent("pre-restore-\(Date().timeIntervalSince1970).lsx")
            try? FileManager.default.copyItem(at: destination, to: safetyBackup)
            try FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.copyItem(at: backup.url, to: destination)
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
    func lockModSettings() {
        lockFile(at: FileLocations.modSettingsFile)
    }

    /// Unlock modsettings.lsx so it can be modified.
    func unlockModSettings() {
        unlockFile(at: FileLocations.modSettingsFile)
    }

    private func lockFile(at url: URL) {
        // Uses chflags(2) to set the user immutable flag (uchg).
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        process.arguments = ["uchg", path]
        try? process.run()
        process.waitUntilExit()
    }

    private func unlockFile(at url: URL) {
        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        process.arguments = ["nouchg", path]
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: - Errors

    enum BackupError: Error, LocalizedError {
        case sourceNotFound

        var errorDescription: String? {
            switch self {
            case .sourceNotFound: return "modsettings.lsx not found - nothing to back up"
            }
        }
    }
}
