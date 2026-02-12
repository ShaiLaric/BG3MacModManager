import Foundation

/// Validates the current mod configuration and produces warnings about potential issues.
final class ModValidationService {

    // MARK: - Public API

    /// Run all validation checks against the current mod state.
    /// Returns a sorted array of warnings (critical first).
    func validate(
        activeMods: [ModInfo],
        inactiveMods: [ModInfo],
        seStatus: ScriptExtenderService.SEStatus?
    ) -> [ModWarning] {
        var warnings: [ModWarning] = []

        warnings.append(contentsOf: checkDuplicateUUIDs(activeMods: activeMods, inactiveMods: inactiveMods))
        warnings.append(contentsOf: checkMissingDependencies(activeMods: activeMods))
        warnings.append(contentsOf: checkDependencyLoadOrder(activeMods: activeMods))
        warnings.append(contentsOf: checkCircularDependencies(activeMods: activeMods))
        warnings.append(contentsOf: checkConflictingMods(activeMods: activeMods))
        warnings.append(contentsOf: checkPhantomMods(activeMods: activeMods))
        warnings.append(contentsOf: checkScriptExtenderRequirements(activeMods: activeMods, seStatus: seStatus))
        warnings.append(contentsOf: checkNoMetadataMods(activeMods: activeMods, inactiveMods: inactiveMods))
        warnings.append(contentsOf: checkModCrashSanityCheck())

        return warnings.sorted { $0.severity > $1.severity }
    }

    /// Validate before saving modsettings.lsx. Returns only warning+ severity issues.
    func validateForSave(
        activeMods: [ModInfo],
        inactiveMods: [ModInfo],
        seStatus: ScriptExtenderService.SEStatus?
    ) -> [ModWarning] {
        return validate(activeMods: activeMods, inactiveMods: inactiveMods, seStatus: seStatus)
            .filter { $0.severity >= .warning }
    }

    // MARK: - Topological Sort (Dependency-Based)

    /// Sort mods based on their dependency graph using Kahn's algorithm.
    /// Returns nil if a circular dependency is detected.
    func topologicalSort(mods: [ModInfo]) -> [ModInfo]? {
        let modsByUUID = Dictionary(mods.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        let activeUUIDs = Set(mods.map(\.uuid))

        // inDegree[uuid] = number of dependencies that are also in the active set
        var inDegree: [String: Int] = [:]
        var dependents: [String: [String]] = [:]  // uuid -> mods that depend on it

        for mod in mods {
            let relevantDeps = mod.dependencies.filter { activeUUIDs.contains($0.uuid) }
            inDegree[mod.uuid] = relevantDeps.count

            for dep in relevantDeps {
                dependents[dep.uuid, default: []].append(mod.uuid)
            }
        }

        // Start with mods that have no in-active-set dependencies
        var queue: [String] = mods
            .filter { (inDegree[$0.uuid] ?? 0) == 0 }
            .map(\.uuid)
        var sorted: [ModInfo] = []

        while !queue.isEmpty {
            let uuid = queue.removeFirst()
            if let mod = modsByUUID[uuid] {
                sorted.append(mod)
            }

            for dependent in dependents[uuid] ?? [] {
                inDegree[dependent, default: 0] -= 1
                if inDegree[dependent] == 0 {
                    queue.append(dependent)
                }
            }
        }

        // If sorted count != mods count, there is a cycle
        guard sorted.count == mods.count else { return nil }
        return sorted
    }

    // MARK: - Individual Checks

    /// Check for duplicate UUIDs across all discovered mods.
    private func checkDuplicateUUIDs(activeMods: [ModInfo], inactiveMods: [ModInfo]) -> [ModWarning] {
        let allMods = activeMods + inactiveMods
        var uuidGroups: [String: [ModInfo]] = [:]

        for mod in allMods {
            uuidGroups[mod.uuid, default: []].append(mod)
        }

        return uuidGroups.compactMap { uuid, mods -> ModWarning? in
            guard mods.count > 1 else { return nil }
            let names = mods.compactMap(\.pakFileName).joined(separator: ", ")
            return ModWarning(
                severity: .critical,
                category: .duplicateUUID,
                message: "Duplicate UUID: \(mods.first?.name ?? uuid)",
                detail: "Files with same UUID (\(uuid)): \(names). Only one should be active.",
                affectedModUUIDs: mods.map(\.uuid),
                suggestedAction: .deactivateMod(uuid: uuid)
            )
        }
    }

    /// Check for missing dependencies among active mods.
    private func checkMissingDependencies(activeMods: [ModInfo]) -> [ModWarning] {
        let activeUUIDs = Set(activeMods.map(\.uuid))
        var warnings: [ModWarning] = []

        for mod in activeMods where !mod.isBasicGameModule {
            for dep in mod.dependencies {
                guard !Constants.builtInModuleUUIDs.contains(dep.uuid) else { continue }

                if !activeUUIDs.contains(dep.uuid) {
                    let depName = dep.name.isEmpty ? dep.uuid : dep.name
                    warnings.append(ModWarning(
                        severity: .warning,
                        category: .missingDependency,
                        message: "\(mod.name) requires \(depName)",
                        detail: "Dependency '\(depName)' (UUID: \(dep.uuid)) is not in the active mod list.",
                        affectedModUUIDs: [mod.uuid],
                        suggestedAction: .installDependency(name: dep.name)
                    ))
                }
            }
        }

        return warnings
    }

    /// Check if dependencies are loaded in the correct order (dependency before dependent).
    private func checkDependencyLoadOrder(activeMods: [ModInfo]) -> [ModWarning] {
        let activeUUIDs = Set(activeMods.map(\.uuid))
        let positionMap = Dictionary(
            activeMods.enumerated().map { ($1.uuid, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var warnings: [ModWarning] = []

        for mod in activeMods where !mod.isBasicGameModule {
            guard let modPosition = positionMap[mod.uuid] else { continue }

            for dep in mod.dependencies {
                guard !Constants.builtInModuleUUIDs.contains(dep.uuid),
                      activeUUIDs.contains(dep.uuid),
                      let depPosition = positionMap[dep.uuid] else { continue }

                if depPosition > modPosition {
                    let depName = dep.name.isEmpty ? dep.uuid : dep.name
                    warnings.append(ModWarning(
                        severity: .warning,
                        category: .wrongLoadOrder,
                        message: "\(mod.name) loads before its dependency \(depName)",
                        detail: "\(mod.name) is at position \(modPosition + 1) but depends on \(depName) at position \(depPosition + 1). Dependencies should load first.",
                        affectedModUUIDs: [mod.uuid, dep.uuid],
                        suggestedAction: .autoSort
                    ))
                }
            }
        }

        return warnings
    }

    /// Detect circular dependencies among active mods using DFS.
    private func checkCircularDependencies(activeMods: [ModInfo]) -> [ModWarning] {
        let activeUUIDs = Set(activeMods.map(\.uuid))
        let modsByUUID = Dictionary(
            activeMods.map { ($0.uuid, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var visited: Set<String> = []
        var inStack: Set<String> = []
        var cycleMods: Set<String> = []

        func dfs(_ uuid: String) -> Bool {
            if inStack.contains(uuid) {
                cycleMods.insert(uuid)
                return true
            }
            if visited.contains(uuid) { return false }

            visited.insert(uuid)
            inStack.insert(uuid)

            if let mod = modsByUUID[uuid] {
                for dep in mod.dependencies where activeUUIDs.contains(dep.uuid) {
                    if dfs(dep.uuid) {
                        cycleMods.insert(uuid)
                    }
                }
            }

            inStack.remove(uuid)
            return false
        }

        for mod in activeMods {
            _ = dfs(mod.uuid)
        }

        if cycleMods.isEmpty { return [] }

        let cycleNames = cycleMods.compactMap { modsByUUID[$0]?.name }.joined(separator: ", ")
        return [ModWarning(
            severity: .critical,
            category: .circularDependency,
            message: "Circular dependency detected",
            detail: "These mods form a dependency cycle: \(cycleNames). This may prevent the game from loading.",
            affectedModUUIDs: Array(cycleMods)
        )]
    }

    /// Check for mods that declare conflicts with other active mods via meta.lsx <Conflicts> node.
    /// Emits one warning per unique conflict pair to avoid duplicates.
    private func checkConflictingMods(activeMods: [ModInfo]) -> [ModWarning] {
        let activeUUIDs = Set(activeMods.map(\.uuid))
        let modsByUUID = Dictionary(
            activeMods.map { ($0.uuid, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // Track pairs we've already warned about so we don't duplicate (A conflicts B == B conflicts A)
        var warnedPairs: Set<String> = []
        var warnings: [ModWarning] = []

        for mod in activeMods {
            for conflict in mod.conflicts {
                guard activeUUIDs.contains(conflict.uuid) else { continue }

                // Canonical pair key: sorted UUIDs
                let pairKey = [mod.uuid, conflict.uuid].sorted().joined(separator: "|")
                guard !warnedPairs.contains(pairKey) else { continue }
                warnedPairs.insert(pairKey)

                let conflictName = modsByUUID[conflict.uuid]?.name ?? (conflict.name.isEmpty ? conflict.uuid : conflict.name)
                warnings.append(ModWarning(
                    severity: .warning,
                    category: .conflictingMods,
                    message: "\(mod.name) conflicts with \(conflictName)",
                    detail: "\(mod.name) declares a conflict with \(conflictName). Having both active may cause issues — check the mod pages for compatibility notes.",
                    affectedModUUIDs: [mod.uuid, conflict.uuid],
                    suggestedAction: .deactivateMod(uuid: conflict.uuid)
                ))
            }
        }

        return warnings
    }

    /// Check for phantom mods (in active list but no PAK file on disk).
    private func checkPhantomMods(activeMods: [ModInfo]) -> [ModWarning] {
        return activeMods.compactMap { mod -> ModWarning? in
            guard !mod.isBasicGameModule else { return nil }
            // .modSettings source means the mod was loaded from modsettings.lsx
            // but no .pak file was found for it on disk
            guard mod.metadataSource == .modSettings else { return nil }
            return ModWarning(
                severity: .critical,
                category: .phantomMod,
                message: "Missing PAK: \(mod.name)",
                detail: "This mod is in modsettings.lsx but no .pak file was found. The game will fail to load it.",
                affectedModUUIDs: [mod.uuid],
                suggestedAction: .deactivateMod(uuid: mod.uuid)
            )
        }
    }

    /// Check for SE mods that are active without Script Extender deployed.
    private func checkScriptExtenderRequirements(
        activeMods: [ModInfo],
        seStatus: ScriptExtenderService.SEStatus?
    ) -> [ModWarning] {
        // If SE is deployed, no issue
        if let status = seStatus, status.isDeployed { return [] }

        let seMods = activeMods.filter(\.requiresScriptExtender)
        guard !seMods.isEmpty else { return [] }

        let names = seMods.map(\.name).joined(separator: ", ")
        return [ModWarning(
            severity: .critical,
            category: .seRequired,
            message: "\(seMods.count) mod(s) require Script Extender but it is not deployed",
            detail: "Mods requiring SE: \(names). These mods will crash the game without bg3se-macos.",
            affectedModUUIDs: seMods.map(\.uuid),
            suggestedAction: .installScriptExtender
        )]
    }

    /// Check for mods discovered only by filename (no metadata).
    private func checkNoMetadataMods(activeMods: [ModInfo], inactiveMods: [ModInfo]) -> [ModWarning] {
        let noMetadata = (activeMods + inactiveMods).filter { $0.metadataSource == .filename }
        return noMetadata.map { mod in
            ModWarning(
                severity: .info,
                category: .noMetadata,
                message: "\(mod.name) has no metadata",
                detail: "This mod's PAK contains no meta.lsx and no info.json was found. UUID and version are derived from the filename.",
                affectedModUUIDs: [mod.uuid]
            )
        }
    }

    /// Check if the ModCrashSanityCheck directory exists.
    /// Since Patch 8 this directory causes BG3 to deactivate externally-managed mods.
    private func checkModCrashSanityCheck() -> [ModWarning] {
        guard FileLocations.modCrashSanityCheckExists else { return [] }
        return [ModWarning(
            severity: .info,
            category: .modCrashSanityCheck,
            message: "ModCrashSanityCheck folder detected",
            detail: "The ModCrashSanityCheck directory exists. Since Patch 8 this can cause the game to deactivate your mods on launch. Delete it to prevent this.",
            suggestedAction: .deleteModCrashSanityCheck
        )]
    }
}
