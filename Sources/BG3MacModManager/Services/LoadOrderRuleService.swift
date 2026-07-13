// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

final class LoadOrderRuleService {
    private let store: VersionedJSONStore<LoadOrderRulePayload>

    init(url: URL = FileLocations.loadOrderRulesFile) {
        store = VersionedJSONStore(url: url, currentSchemaVersion: 1)
    }

    func loadRules() throws -> [LoadOrderRule] {
        try store.load()?.rules ?? []
    }

    func saveRules(_ rules: [LoadOrderRule]) throws {
        try store.save(LoadOrderRulePayload(rules: rules))
    }

    @discardableResult
    func resetPreservingExisting() throws -> URL? {
        try store.resetPreservingExisting(with: .empty)
    }

    func validate(_ rule: LoadOrderRule) throws {
        guard !Constants.builtInModuleUUIDs.contains(rule.sourceUUID) else {
            throw RuleError.builtInModule
        }

        if rule.kind.needsTarget {
            guard let target = rule.targetUUID, !target.isEmpty else {
                throw RuleError.targetRequired
            }
            guard target != rule.sourceUUID else { throw RuleError.selfReference }
            guard !Constants.builtInModuleUUIDs.contains(target) else {
                throw RuleError.builtInModule
            }
        }

        if rule.kind.needsPosition {
            guard let position = rule.position, position > 0 else {
                throw RuleError.invalidPosition
            }
        }
    }

    enum RuleError: Error, LocalizedError {
        case targetRequired
        case selfReference
        case invalidPosition
        case builtInModule

        var errorDescription: String? {
            switch self {
            case .targetRequired:
                return "Choose another mod for this load-order rule."
            case .selfReference:
                return "A mod cannot be ordered relative to itself."
            case .invalidPosition:
                return "Pinned positions must be 1 or greater."
            case .builtInModule:
                return "Built-in game modules cannot be load-order rule targets."
            }
        }
    }
}
