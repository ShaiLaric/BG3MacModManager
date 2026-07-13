// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum ModIdentity {
    /// Accepts only well-formed UUIDs and returns the canonical lowercase representation.
    static func normalizedUUID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let uuid = UUID(uuidString: trimmed) else { return nil }
        return uuid.uuidString.lowercased()
    }

    /// Case-insensitive comparison key for already-trusted persisted identifiers.
    static func comparisonKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
