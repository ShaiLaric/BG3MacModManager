// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

final class ModUpdateHistoryService {
    private let store: VersionedJSONStore<ModUpdateHistoryPayload>

    init(url: URL = FileLocations.modUpdateHistoryFile) {
        store = VersionedJSONStore(url: url, currentSchemaVersion: 1)
    }

    func load() throws -> ModUpdateHistoryPayload {
        try store.load() ?? ModUpdateHistoryPayload(records: [], provenanceByUUID: [:])
    }

    func save(_ payload: ModUpdateHistoryPayload) throws {
        try store.save(payload)
    }
}
