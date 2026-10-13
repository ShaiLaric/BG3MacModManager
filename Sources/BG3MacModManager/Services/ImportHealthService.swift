// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Evaluates the configuration that would result from activating the newly imported mods.
/// File installation and activation remain separate, explicit operations.
struct ImportHealthService {
    func report(
        importedMods: [ModInfo],
        activationCandidates: [ModInfo],
        activeMods: [ModInfo],
        inactiveMods: [ModInfo],
        duplicateGroups: [[ModInfo]],
        seStatus: ScriptExtenderService.SEStatus?,
        loadOrderRules: [LoadOrderRule],
        replacedFileCount: Int,
        importErrors: [String]
    ) -> ImportHealthReport {
        ImportHealthReport(
            importedMods: importedMods,
            activationCandidates: activationCandidates,
            findings: ModValidationService().validateImport(
                importedMods: importedMods,
                activationCandidates: activationCandidates,
                activeMods: activeMods,
                inactiveMods: inactiveMods,
                duplicateGroups: duplicateGroups,
                seStatus: seStatus,
                loadOrderRules: loadOrderRules
            ),
            replacedFileCount: replacedFileCount,
            importErrors: importErrors
        )
    }
}
