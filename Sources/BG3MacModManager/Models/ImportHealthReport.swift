// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

struct ImportHealthReport: Identifiable, Sendable {
    let id = UUID()
    let importedMods: [ModInfo]
    let activationCandidates: [ModInfo]
    let findings: [ModWarning]
    let replacedFileCount: Int
    let importErrors: [String]

    var criticalCount: Int { findings.filter { $0.severity == .critical }.count }
    var warningCount: Int { findings.filter { $0.severity == .warning }.count }
}
