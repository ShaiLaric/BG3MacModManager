// SPDX-License-Identifier: GPL-3.0-or-later

import CryptoKit
import Foundation

/// Keeps the exact successful export alongside its path and fingerprint.
struct ModSettingsRecoveryService {
    let settingsURL: URL
    let snapshotURL: URL
    let baselineURL: URL

    struct Snapshot: Codable {
        let path: String
        let data: Data
        let hash: String
    }

    init(
        settingsURL: URL = FileLocations.modSettingsFile,
        snapshotURL: URL = FileLocations.appSupportDirectory.appendingPathComponent("last_saved_modsettings.json"),
        baselineURL: URL = FileLocations.lastExportHashFile
    ) {
        self.settingsURL = settingsURL
        self.snapshotURL = snapshotURL
        self.baselineURL = baselineURL
    }

    func save(_ data: Data, fileManager: FileManager = .default) throws {
        _ = try ModSettingsService().read(data: data)
        let hash = Self.hash(data)
        let snapshot = Snapshot(path: settingsURL.path, data: data, hash: hash)
        let staging = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: staging) }
        let settings = staging.appendingPathComponent("settings")
        let document = staging.appendingPathComponent("snapshot")
        let baseline = staging.appendingPathComponent("baseline")
        try data.write(to: settings)
        try JSONEncoder().encode(snapshot).write(to: document)
        try Data(ModSettingsExportBaseline(hash: hash, path: settingsURL.path).fileContents.utf8).write(to: baseline)
        try TransactionalFileService.replaceFiles([
            .init(source: settings, destination: settingsURL),
            .init(source: document, destination: snapshotURL),
            .init(source: baseline, destination: baselineURL),
        ], fileManager: fileManager)
    }

    func savedData() throws -> Data {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { throw RecoveryError.snapshotMissing }
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: snapshotURL))
        guard snapshot.path == settingsURL.path, Self.hash(snapshot.data) == snapshot.hash else {
            throw RecoveryError.invalidSnapshot
        }
        _ = try ModSettingsService().read(data: snapshot.data)
        return snapshot.data
    }

    static func hash(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    enum RecoveryError: Error, LocalizedError {
        case invalidSnapshot
        case snapshotMissing
        var errorDescription: String? {
            switch self {
            case .invalidSnapshot:
                return "The last saved load order is damaged or belongs to a different BG3 location. Choose a backup manually."
            case .snapshotMissing:
                return "No saved load-order snapshot is available yet. Choose a backup manually from Backups."
            }
        }
    }
}
