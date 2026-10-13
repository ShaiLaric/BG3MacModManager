// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Accounts for durable recovery data. Cleanup is explicit and retains active update backups.
struct BackupStorageService: Sendable {
    let appSupportDirectory: URL

    struct Usage: Sendable {
        let settingsBytes: Int64
        let updateBytes: Int64
        let importBytes: Int64
        var totalBytes: Int64 { settingsBytes + updateBytes + importBytes }
    }

    init(appSupportDirectory: URL = FileLocations.appSupportDirectory) {
        self.appSupportDirectory = appSupportDirectory
    }

    func usage() throws -> Usage {
        try Usage(
            settingsBytes: bytes(in: directory("Backups")),
            updateBytes: bytes(in: directory("ModUpdateBackups")),
            importBytes: bytes(in: directory("ImportBackups"))
        )
    }

    /// Discard old import recovery copies, restored update copies and unreferenced update
    /// directories. A corrupt history blocks cleanup rather than making every backup orphaned.
    func cleanExpiredRecoveryCopies(olderThanDays days: Int, now: Date = Date()) throws {
        guard days > 0 else { return }
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        let payload = try ModUpdateHistoryService(
            url: appSupportDirectory.appendingPathComponent("mod_update_history.json")
        ).load()
        let active = Set(payload.records.filter { $0.status == .installed }.map(\.backupDirectoryName))
        let restored = Dictionary(payload.records.filter { $0.status == .restored }.map {
            ($0.backupDirectoryName, $0.restoredAt ?? $0.installedAt)
        }, uniquingKeysWith: { first, _ in first })
        for folder in [directory("ImportBackups"), directory("ModUpdateBackups")] {
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            for url in try FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey]
            ) {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .contentModificationDateKey])
                guard values.isDirectory == true, values.isSymbolicLink != true,
                      UUID(uuidString: url.lastPathComponent) != nil,
                      !active.contains(url.lastPathComponent),
                      let date = restored[url.lastPathComponent] ?? values.contentModificationDate,
                      date < cutoff else { continue }
                try FileManager.default.removeItem(at: url)
            }
        }
    }

    private func directory(_ name: String) -> URL { appSupportDirectory.appendingPathComponent(name) }

    private func bytes(in directory: URL) throws -> Int64 {
        guard FileManager.default.fileExists(atPath: directory.path) else { return 0 }
        var readError: Error?
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys)) { _, error in
            readError = error
            return false
        }
        var total: Int64 = 0
        while let url = enumerator?.nextObject() as? URL {
            try Task.checkCancellation()
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { enumerator?.skipDescendants(); continue }
            if values.isRegularFile == true { total += Int64(values.fileSize ?? 0) }
        }
        if let readError { throw readError }
        return total
    }
}
