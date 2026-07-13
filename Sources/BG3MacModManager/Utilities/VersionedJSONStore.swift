// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// On-disk envelope for app data that needs explicit schema migrations.
struct VersionedDocument<Payload: Codable>: Codable {
    let schemaVersion: Int
    let payload: Payload
}

/// Small synchronous JSON store for app-support documents.
///
/// Services own their stores and decide whether a corrupt/unsupported document should be reset.
/// Resetting is explicit so an unreadable user document is never silently discarded.
struct VersionedJSONStore<Payload: Codable> {
    typealias Migration = (_ storedVersion: Int, _ documentData: Data) throws -> Payload

    let url: URL
    let currentSchemaVersion: Int

    init(url: URL, currentSchemaVersion: Int) {
        precondition(currentSchemaVersion > 0, "Schema versions must be positive")
        self.url = url
        self.currentSchemaVersion = currentSchemaVersion
    }

    /// Load the document, returning nil when it has never been created.
    /// Older schemas require an explicit migration and are rewritten after migration succeeds.
    func load(migrate: Migration? = nil) throws -> Payload? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw StoreError.readFailed(url, error.localizedDescription)
        }

        let header: DocumentHeader
        do {
            header = try JSONDecoder().decode(DocumentHeader.self, from: data)
        } catch {
            throw StoreError.corrupt(url, error.localizedDescription)
        }

        if header.schemaVersion > currentSchemaVersion {
            throw StoreError.unsupportedVersion(
                stored: header.schemaVersion,
                supported: currentSchemaVersion,
                url: url
            )
        }

        if header.schemaVersion < currentSchemaVersion {
            guard let migrate else {
                throw StoreError.migrationRequired(
                    stored: header.schemaVersion,
                    supported: currentSchemaVersion,
                    url: url
                )
            }

            let migrated: Payload
            do {
                migrated = try migrate(header.schemaVersion, data)
            } catch {
                throw StoreError.migrationFailed(url, error.localizedDescription)
            }
            try save(migrated)
            return migrated
        }

        do {
            return try JSONDecoder.bg3Versioned.decode(
                VersionedDocument<Payload>.self,
                from: data
            ).payload
        } catch {
            throw StoreError.corrupt(url, error.localizedDescription)
        }
    }

    /// Atomically persist the current schema in a stable, human-readable format.
    func save(_ payload: Payload) throws {
        let document = VersionedDocument(
            schemaVersion: currentSchemaVersion,
            payload: payload
        )

        let data: Data
        do {
            data = try JSONEncoder.bg3Versioned.encode(document)
        } catch {
            throw StoreError.encodingFailed(url, error.localizedDescription)
        }

        do {
            try FileLocations.ensureDirectoryExists(url.deletingLastPathComponent())
            try data.write(to: url, options: .atomic)
        } catch {
            throw StoreError.writeFailed(url, error.localizedDescription)
        }
    }

    /// Preserve the existing bytes next to the document, then write a fresh payload.
    /// Returns the backup URL, or nil when no prior document existed.
    @discardableResult
    func resetPreservingExisting(with payload: Payload) throws -> URL? {
        let backupURL = try backupExistingDocument()
        do {
            try save(payload)
        } catch {
            if let backupURL {
                try? FileManager.default.removeItem(at: url)
                try? FileManager.default.copyItem(at: backupURL, to: url)
            }
            throw error
        }
        return backupURL
    }

    @discardableResult
    func backupExistingDocument() throws -> URL? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let backupURL = url.deletingLastPathComponent().appendingPathComponent(
            "\(url.lastPathComponent).unreadable-\(UUID().uuidString).backup"
        )
        do {
            try FileManager.default.copyItem(at: url, to: backupURL)
            return backupURL
        } catch {
            throw StoreError.backupFailed(url, error.localizedDescription)
        }
    }

    enum StoreError: Error, LocalizedError {
        case readFailed(URL, String)
        case corrupt(URL, String)
        case unsupportedVersion(stored: Int, supported: Int, url: URL)
        case migrationRequired(stored: Int, supported: Int, url: URL)
        case migrationFailed(URL, String)
        case encodingFailed(URL, String)
        case writeFailed(URL, String)
        case backupFailed(URL, String)

        var errorDescription: String? {
            switch self {
            case .readFailed(let url, let detail):
                return "Could not read \(url.lastPathComponent): \(detail)"
            case .corrupt(let url, let detail):
                return "\(url.lastPathComponent) is corrupt: \(detail)"
            case .unsupportedVersion(let stored, let supported, let url):
                return "\(url.lastPathComponent) uses schema \(stored), but this app supports up to schema \(supported)."
            case .migrationRequired(let stored, let supported, let url):
                return "\(url.lastPathComponent) requires migration from schema \(stored) to \(supported)."
            case .migrationFailed(let url, let detail):
                return "Could not migrate \(url.lastPathComponent): \(detail)"
            case .encodingFailed(let url, let detail):
                return "Could not encode \(url.lastPathComponent): \(detail)"
            case .writeFailed(let url, let detail):
                return "Could not write \(url.lastPathComponent): \(detail)"
            case .backupFailed(let url, let detail):
                return "Could not preserve \(url.lastPathComponent) before resetting it: \(detail)"
            }
        }
    }
}

private struct DocumentHeader: Decodable {
    let schemaVersion: Int
}

private extension JSONEncoder {
    static var bg3Versioned: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var bg3Versioned: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
