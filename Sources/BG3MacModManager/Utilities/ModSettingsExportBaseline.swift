// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The SHA-256 of the last modsettings.lsx this app wrote, together with the
/// path it was written to. Recording the path keeps a fingerprint taken from
/// one BG3 installation from being compared against another after the user
/// changes the BG3 User Data location.
struct ModSettingsExportBaseline: Equatable {
    let hash: String
    /// `nil` for baselines written before the path was recorded.
    let path: String?

    init(hash: String, path: String?) {
        self.hash = hash
        self.path = path
    }

    /// Parse the stored file: the hash on the first line, then the path.
    /// Files written by older versions contain only the hash.
    init?(fileContents: String) {
        let parts = fileContents.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        let hash = parts.first.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
        guard !hash.isEmpty else { return nil }

        let path = parts.count > 1
            ? parts[1].trimmingCharacters(in: .newlines)
            : ""
        self.init(hash: hash, path: path.isEmpty ? nil : path)
    }

    var fileContents: String {
        guard let path else { return hash }
        return "\(hash)\n\(path)"
    }

    /// Whether this baseline describes the modsettings.lsx at `modSettingsPath`.
    /// Baselines without a recorded path predate configurable locations, so
    /// they can only describe `legacyPath` (the default modsettings.lsx).
    func applies(to modSettingsPath: String, legacyPath: String) -> Bool {
        (path ?? legacyPath) == modSettingsPath
    }
}
