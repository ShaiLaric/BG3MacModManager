// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct SaveProfileComparator {
    func compare(
        save: SaveGameSummary,
        profile: ModProfile,
        activeMods: [ModInfo],
        installedMods: [ModInfo]
    ) -> SaveProfileComparison {
        let expectedOrder = profile.activeModUUIDs.compactMap(ModIdentity.normalizedUUID)
            .filter { !Constants.builtInModuleUUIDs.contains($0) }
        let currentOrder = activeMods.compactMap { ModIdentity.normalizedUUID($0.uuid) }
            .filter { !Constants.builtInModuleUUIDs.contains($0) }
        let installedByUUID = Dictionary(
            installedMods.compactMap { mod -> (String, ModInfo)? in
                ModIdentity.normalizedUUID(mod.uuid).map { ($0, mod) }
            },
            uniquingKeysWith: { first, second in
                first.pakFilePath != nil ? first : second
            }
        )
        let expectedByUUID = Dictionary(
            profile.mods.compactMap { entry -> (String, ModProfileEntry)? in
                ModIdentity.normalizedUUID(entry.uuid).map { ($0, entry) }
            },
            uniquingKeysWith: { first, _ in first }
        )

        let missing = expectedOrder.filter { installedByUUID[$0]?.pakFilePath == nil }
        let expectedSet = Set(expectedOrder)
        let extra = currentOrder.filter { !expectedSet.contains($0) }
        let versions = expectedOrder.compactMap { uuid -> SaveProfileComparison.VersionDifference? in
            guard let expected = expectedByUUID[uuid], let installed = installedByUUID[uuid],
                  expected.version64 != installed.version64 else { return nil }
            return .init(
                uuid: uuid,
                name: expected.name,
                expectedVersion64: expected.version64,
                installedVersion64: installed.version64
            )
        }
        let comparableCurrent = currentOrder.filter(expectedSet.contains)
        let expectedInstalled = expectedOrder.filter { installedByUUID[$0]?.pakFilePath != nil }
        let saveOrder = save.mods.map(\.uuid)

        return SaveProfileComparison(
            missingInstalledUUIDs: missing,
            extraActiveUUIDs: extra,
            versionDifferences: versions,
            currentOrderDiffers: comparableCurrent != expectedInstalled,
            saveOrderDiffersFromProfile: save.isReadable && saveOrder != expectedOrder
        )
    }
}
