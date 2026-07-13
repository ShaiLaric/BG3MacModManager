// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct SaveGameArchiveMetadata: Equatable, Sendable {
    let gameID: String?
    let mods: [SaveModEntry]
}

struct SaveGameArchiveReader: Sendable {
    enum ArchiveError: Error, LocalizedError {
        case noSupportedMetadata

        var errorDescription: String? {
            "Neither modern meta.lsf nor legacy modsettings.lsx metadata was found in the save archive."
        }
    }

    func read(from url: URL) throws -> SaveGameArchiveMetadata {
        let entries = try PakReader.listFiles(at: url)

        if let settingsEntry = entries.first(where: { normalized($0.name).hasSuffix("modsettings.lsx") }),
           let metadata = try? readLegacy(entryName: settingsEntry.name, from: url) {
            return metadata
        }

        if let metaEntry = entries.first(where: { normalized($0.name) == "meta.lsf" }) {
            let data = try PakReader.extractFile(named: metaEntry.name, from: url)
            let result = try LarianSaveMetadataReader().read(data: data)
            return SaveGameArchiveMetadata(
                gameID: result.gameID,
                mods: result.mods.filter { !Constants.builtInModuleUUIDs.contains($0.uuid) }
            )
        }

        throw ArchiveError.noSupportedMetadata
    }

    private func readLegacy(entryName: String, from url: URL) throws -> SaveGameArchiveMetadata {
        let data = try PakReader.extractFile(named: entryName, from: url)
        let settings = try ModSettingsService().read(data: data)
        let mods = settings.modOrder.compactMap { rawUUID -> SaveModEntry? in
            guard let uuid = ModIdentity.normalizedUUID(rawUUID),
                  !Constants.builtInModuleUUIDs.contains(uuid) else { return nil }
            let metadata = settings.mods[uuid]
            return SaveModEntry(
                uuid: uuid,
                name: metadata?.name ?? uuid,
                folder: metadata?.folder ?? "",
                version64: Int64(metadata?.version64 ?? "") ?? 0,
                md5: metadata?.md5 ?? ""
            )
        }
        return SaveGameArchiveMetadata(gameID: nil, mods: mods)
    }

    private func normalized(_ path: String) -> String {
        path.replacingOccurrences(of: "\\", with: "/").lowercased()
    }
}
