// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// A persistent constraint applied to non-game mods.
struct LoadOrderRule: Identifiable, Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case before
        case after
        case pinPosition
        case pinFirst
        case pinLast

        var displayName: String {
            switch self {
            case .before: return "Always Before"
            case .after: return "Always After"
            case .pinPosition: return "Pin to Position"
            case .pinFirst: return "Pin First"
            case .pinLast: return "Pin Last"
            }
        }

        var needsTarget: Bool { self == .before || self == .after }
        var needsPosition: Bool { self == .pinPosition }
    }

    let id: UUID
    var kind: Kind
    var sourceUUID: String
    var targetUUID: String?
    var position: Int?
    var isEnabled: Bool

    /// Nil means global. Reserved for profile-specific rules without changing the schema shape.
    var profileID: UUID?

    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: Kind,
        sourceUUID: String,
        targetUUID: String? = nil,
        position: Int? = nil,
        isEnabled: Bool = true,
        profileID: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.sourceUUID = ModIdentity.comparisonKey(sourceUUID)
        self.targetUUID = targetUUID.map(ModIdentity.comparisonKey)
        self.position = position
        self.isEnabled = isEnabled
        self.profileID = profileID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct LoadOrderRulePayload: Codable, Equatable, Sendable {
    var rules: [LoadOrderRule]

    static let empty = LoadOrderRulePayload(rules: [])
}

struct LoadOrderRuleViolation: Identifiable, Equatable, Sendable {
    let ruleID: UUID
    let message: String
    let affectedModUUIDs: [String]

    var id: UUID { ruleID }
}
