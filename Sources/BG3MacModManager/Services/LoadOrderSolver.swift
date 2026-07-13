// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Deterministic global ordering for dependencies, user rules, pins, and category preferences.
struct LoadOrderSolver {
    enum SortMode: Sendable {
        case dependenciesOnly
        case smart
    }

    enum ConflictKind: String, Sendable {
        case cycle
        case pinCollision
        case conflictingPins
        case pinOutOfRange
        case pinBlocked
        case duplicateIdentity
    }

    struct Conflict: Error, Equatable, Sendable {
        let kind: ConflictKind
        let message: String
        let affectedModUUIDs: [String]
        let ruleIDs: [UUID]
    }

    enum Result: Equatable, Sendable {
        case ordered([ModInfo])
        case conflict(Conflict)
    }

    func solve(
        mods: [ModInfo],
        rules: [LoadOrderRule] = [],
        mode: SortMode
    ) -> Result {
        guard !mods.isEmpty else { return .ordered([]) }

        let indexedMods = mods.enumerated().map { index, mod in
            (index, ModIdentity.comparisonKey(mod.uuid), mod)
        }
        let modsByUUID = Dictionary(
            indexedMods.map { ($0.1, $0.2) },
            uniquingKeysWith: { first, _ in first }
        )
        let originalIndex = Dictionary(
            indexedMods.map { ($0.1, $0.0) },
            uniquingKeysWith: { first, _ in first }
        )
        let activeUUIDs = Set(modsByUUID.keys)

        if modsByUUID.count != mods.count {
            let duplicates = Dictionary(grouping: indexedMods, by: { $0.1 })
                .filter { $0.value.count > 1 }
                .keys
                .sorted()
            return .conflict(Conflict(
                kind: .duplicateIdentity,
                message: "The active order contains duplicate mod UUIDs. Resolve duplicates before sorting.",
                affectedModUUIDs: duplicates,
                ruleIDs: []
            ))
        }

        var adjacency = Dictionary(uniqueKeysWithValues: activeUUIDs.map { ($0, Set<String>()) })
        var inDegree = Dictionary(uniqueKeysWithValues: activeUUIDs.map { ($0, 0) })
        var edgeRuleIDs: [Edge: Set<UUID>] = [:]

        func addEdge(from: String, to: String, ruleID: UUID? = nil) {
            guard activeUUIDs.contains(from), activeUUIDs.contains(to) else { return }
            let inserted = adjacency[from, default: []].insert(to).inserted
            if inserted {
                inDegree[to, default: 0] += 1
            }
            if let ruleID {
                edgeRuleIDs[Edge(from: from, to: to), default: []].insert(ruleID)
            }
        }

        for (_, uuid, mod) in indexedMods {
            for dependency in mod.dependencies {
                let dependencyUUID = ModIdentity.comparisonKey(dependency.uuid)
                if activeUUIDs.contains(dependencyUUID) {
                    addEdge(from: dependencyUUID, to: uuid)
                }
            }
        }

        let enabledRules = rules.filter { $0.isEnabled && $0.profileID == nil }
        for rule in enabledRules {
            let source = ModIdentity.comparisonKey(rule.sourceUUID)
            guard activeUUIDs.contains(source) else { continue }
            switch rule.kind {
            case .before:
                if let target = rule.targetUUID.map(ModIdentity.comparisonKey),
                   activeUUIDs.contains(target) {
                    addEdge(from: source, to: target, ruleID: rule.id)
                }
            case .after:
                if let target = rule.targetUUID.map(ModIdentity.comparisonKey),
                   activeUUIDs.contains(target) {
                    addEdge(from: target, to: source, ruleID: rule.id)
                }
            case .pinPosition, .pinFirst, .pinLast:
                break
            }
        }

        switch buildPins(rules: enabledRules, activeUUIDs: activeUUIDs, count: mods.count) {
        case .failure(let conflict):
            return .conflict(conflict)
        case .success(let pins):
            return order(
                modsByUUID: modsByUUID,
                originalIndex: originalIndex,
                adjacency: adjacency,
                inDegree: inDegree,
                edgeRuleIDs: edgeRuleIDs,
                pins: pins,
                mode: mode
            )
        }
    }

    static func violations(
        mods: [ModInfo],
        rules: [LoadOrderRule]
    ) -> [LoadOrderRuleViolation] {
        let userMods = mods.filter { !$0.isBasicGameModule }
        let positions = Dictionary(
            userMods.enumerated().map {
                (ModIdentity.comparisonKey($0.element.uuid), $0.offset + 1)
            },
            uniquingKeysWith: { first, _ in first }
        )

        return rules.compactMap { rule in
            guard rule.isEnabled, rule.profileID == nil,
                  let sourcePosition = positions[ModIdentity.comparisonKey(rule.sourceUUID)] else {
                return nil
            }

            let message: String?
            var affected = [rule.sourceUUID]
            switch rule.kind {
            case .before:
                guard let target = rule.targetUUID,
                      let targetPosition = positions[ModIdentity.comparisonKey(target)] else {
                    return nil
                }
                affected.append(target)
                message = sourcePosition < targetPosition
                    ? nil
                    : "Rule violated: mod at position \(sourcePosition) must load before position \(targetPosition)."
            case .after:
                guard let target = rule.targetUUID,
                      let targetPosition = positions[ModIdentity.comparisonKey(target)] else {
                    return nil
                }
                affected.append(target)
                message = sourcePosition > targetPosition
                    ? nil
                    : "Rule violated: mod at position \(sourcePosition) must load after position \(targetPosition)."
            case .pinPosition:
                guard let position = rule.position else { return nil }
                message = sourcePosition == position
                    ? nil
                    : "Rule violated: mod is at position \(sourcePosition), but is pinned to position \(position)."
            case .pinFirst:
                message = sourcePosition == 1
                    ? nil
                    : "Rule violated: mod is pinned to the first user-mod position."
            case .pinLast:
                message = sourcePosition == userMods.count
                    ? nil
                    : "Rule violated: mod is pinned to the last user-mod position."
            }

            guard let message else { return nil }
            return LoadOrderRuleViolation(
                ruleID: rule.id,
                message: message,
                affectedModUUIDs: affected.map(ModIdentity.comparisonKey)
            )
        }
    }

    private func buildPins(
        rules: [LoadOrderRule],
        activeUUIDs: Set<String>,
        count: Int
    ) -> Swift.Result<Pins, Conflict> {
        var positionByUUID: [String: (position: Int, ruleIDs: [UUID])] = [:]
        var uuidByPosition: [Int: (uuid: String, ruleIDs: [UUID])] = [:]

        for rule in rules {
            let uuid = ModIdentity.comparisonKey(rule.sourceUUID)
            guard activeUUIDs.contains(uuid) else { continue }

            let position: Int
            switch rule.kind {
            case .pinPosition:
                guard let value = rule.position else { continue }
                position = value
            case .pinFirst:
                position = 1
            case .pinLast:
                position = count
            case .before, .after:
                continue
            }

            guard position >= 1, position <= count else {
                return .failure(Conflict(
                    kind: .pinOutOfRange,
                    message: "Pinned position \(position) is outside the active user-mod range 1...\(count).",
                    affectedModUUIDs: [uuid],
                    ruleIDs: [rule.id]
                ))
            }

            if let existing = positionByUUID[uuid], existing.position != position {
                return .failure(Conflict(
                    kind: .conflictingPins,
                    message: "One mod is pinned to both position \(existing.position) and position \(position).",
                    affectedModUUIDs: [uuid],
                    ruleIDs: existing.ruleIDs + [rule.id]
                ))
            }

            if let existing = uuidByPosition[position], existing.uuid != uuid {
                return .failure(Conflict(
                    kind: .pinCollision,
                    message: "Two mods are pinned to position \(position).",
                    affectedModUUIDs: [existing.uuid, uuid],
                    ruleIDs: existing.ruleIDs + [rule.id]
                ))
            }

            positionByUUID[uuid] = (
                position,
                (positionByUUID[uuid]?.ruleIDs ?? []) + [rule.id]
            )
            uuidByPosition[position] = (
                uuid,
                (uuidByPosition[position]?.ruleIDs ?? []) + [rule.id]
            )
        }

        return .success(Pins(positionByUUID: positionByUUID, uuidByPosition: uuidByPosition))
    }

    private func order(
        modsByUUID: [String: ModInfo],
        originalIndex: [String: Int],
        adjacency: [String: Set<String>],
        inDegree initialInDegree: [String: Int],
        edgeRuleIDs: [Edge: Set<UUID>],
        pins: Pins,
        mode: SortMode
    ) -> Result {
        var inDegree = initialInDegree
        var remaining = Set(modsByUUID.keys)
        var ordered: [ModInfo] = []

        for position in 1...modsByUUID.count {
            let uuid: String
            if let forced = pins.uuidByPosition[position] {
                guard remaining.contains(forced.uuid) else {
                    return .conflict(Conflict(
                        kind: .pinBlocked,
                        message: "The mod pinned to position \(position) was already constrained to another position.",
                        affectedModUUIDs: [forced.uuid],
                        ruleIDs: forced.ruleIDs
                    ))
                }
                guard inDegree[forced.uuid, default: 0] == 0 else {
                    let blockers = remaining.filter {
                        adjacency[$0, default: []].contains(forced.uuid)
                    }.sorted()
                    let contributingRules = blockers.flatMap {
                        edgeRuleIDs[Edge(from: $0, to: forced.uuid)] ?? []
                    }
                    return .conflict(Conflict(
                        kind: .pinBlocked,
                        message: "The mod pinned to position \(position) must load after an unresolved dependency or rule target.",
                        affectedModUUIDs: blockers + [forced.uuid],
                        ruleIDs: Array(Set(forced.ruleIDs + contributingRules)).sorted { $0.uuidString < $1.uuidString }
                    ))
                }
                uuid = forced.uuid
            } else {
                let candidates = remaining.filter {
                    inDegree[$0, default: 0] == 0 && pins.positionByUUID[$0] == nil
                }
                guard let selected = candidates.min(by: {
                    isHigherPriority(
                        $0,
                        than: $1,
                        modsByUUID: modsByUUID,
                        originalIndex: originalIndex,
                        mode: mode
                    )
                }) else {
                    if let cycle = findCycle(in: remaining, adjacency: adjacency) {
                        let ruleIDs = zip(cycle, cycle.dropFirst() + [cycle[0]]).flatMap {
                            edgeRuleIDs[Edge(from: $0.0, to: $0.1)] ?? []
                        }
                        return .conflict(Conflict(
                            kind: .cycle,
                            message: "Dependencies and load-order rules form a cycle.",
                            affectedModUUIDs: cycle,
                            ruleIDs: Array(Set(ruleIDs)).sorted { $0.uuidString < $1.uuidString }
                        ))
                    }

                    let futurePinned = remaining.compactMap { uuid -> UUID? in
                        pins.positionByUUID[uuid]?.ruleIDs.first
                    }
                    return .conflict(Conflict(
                        kind: .pinBlocked,
                        message: "Pinned positions leave no eligible mod for position \(position).",
                        affectedModUUIDs: remaining.sorted(),
                        ruleIDs: Array(Set(futurePinned)).sorted { $0.uuidString < $1.uuidString }
                    ))
                }
                uuid = selected
            }

            guard let mod = modsByUUID[uuid] else { continue }
            ordered.append(mod)
            remaining.remove(uuid)
            for dependent in adjacency[uuid, default: []] where remaining.contains(dependent) {
                inDegree[dependent, default: 0] -= 1
            }
        }

        return .ordered(ordered)
    }

    private func isHigherPriority(
        _ lhs: String,
        than rhs: String,
        modsByUUID: [String: ModInfo],
        originalIndex: [String: Int],
        mode: SortMode
    ) -> Bool {
        if mode == .smart {
            let lhsTier = modsByUUID[lhs]?.category?.rawValue ?? 3
            let rhsTier = modsByUUID[rhs]?.category?.rawValue ?? 3
            if lhsTier != rhsTier { return lhsTier < rhsTier }
        }
        let lhsIndex = originalIndex[lhs] ?? .max
        let rhsIndex = originalIndex[rhs] ?? .max
        if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
        return lhs < rhs
    }

    private func findCycle(
        in nodes: Set<String>,
        adjacency: [String: Set<String>]
    ) -> [String]? {
        var visited = Set<String>()
        var active = Set<String>()
        var stack: [String] = []

        func visit(_ node: String) -> [String]? {
            visited.insert(node)
            active.insert(node)
            stack.append(node)
            defer {
                _ = stack.popLast()
                active.remove(node)
            }

            for next in adjacency[node, default: []].sorted() where nodes.contains(next) {
                if active.contains(next), let index = stack.firstIndex(of: next) {
                    return Array(stack[index...])
                }
                if !visited.contains(next), let cycle = visit(next) {
                    return cycle
                }
            }
            return nil
        }

        for node in nodes.sorted() where !visited.contains(node) {
            if let cycle = visit(node) { return cycle }
        }
        return nil
    }
}

private struct Edge: Hashable {
    let from: String
    let to: String
}

private struct Pins {
    let positionByUUID: [String: (position: Int, ruleIDs: [UUID])]
    let uuidByPosition: [Int: (uuid: String, ruleIDs: [UUID])]
}
