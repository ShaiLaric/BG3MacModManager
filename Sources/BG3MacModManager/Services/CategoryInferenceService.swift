// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Infers a ModCategory for mods using tag heuristics and name heuristics.
/// Users can override inferred categories; overrides are persisted to disk.
final class CategoryInferenceService {

    // MARK: - Public API

    /// Infer a category for a mod. Checks (in order):
    /// 1. User override (persisted)
    /// 2. Tag-based heuristics
    /// 3. Name-based heuristics
    /// Returns nil if no category can be inferred (mod stays unsorted).
    func inferCategory(for mod: ModInfo) -> ModCategory? {
        if let override = userOverrides[mod.uuid] {
            return override
        }
        if let tagBased = inferFromTags(mod.tags) {
            return tagBased
        }
        if let nameBased = inferFromName(mod.name) {
            return nameBased
        }
        return nil
    }

    /// Set a user override for a mod's category. Pass nil to clear.
    func setOverride(_ category: ModCategory?, for modUUID: String) {
        if let category = category {
            userOverrides[modUUID] = category
        } else {
            userOverrides.removeValue(forKey: modUUID)
        }
        saveOverrides()
    }

    /// Returns the user override for a mod, if any.
    func override(for modUUID: String) -> ModCategory? {
        userOverrides[modUUID]
    }

    // MARK: - User Overrides (Persisted)

    private var userOverrides: [String: ModCategory] = [:]

    private static var overridesURL: URL {
        FileLocations.appSupportDirectory.appendingPathComponent("category_overrides.json")
    }

    init() {
        loadOverrides()
    }

    private func loadOverrides() {
        guard let data = try? Data(contentsOf: Self.overridesURL),
              let decoded = try? JSONDecoder().decode([String: ModCategory].self, from: data) else {
            return
        }
        userOverrides = decoded
    }

    private func saveOverrides() {
        do {
            try FileLocations.ensureDirectoryExists(FileLocations.appSupportDirectory)
            let data = try JSONEncoder().encode(userOverrides)
            try data.write(to: Self.overridesURL, options: .atomic)
        } catch {
            // Non-fatal: overrides just won't persist
        }
    }

    // MARK: - Tag Heuristics

    private func inferFromTags(_ tags: [String]) -> ModCategory? {
        let lowered = tags.map { $0.lowercased() }

        // Late loaders (check first — "patch" in tags is a strong signal)
        for tag in lowered {
            if tag.contains("compatibility") || tag == "patch" || tag == "combiner" {
                return .lateLoader
            }
        }

        // Frameworks
        for tag in lowered {
            if tag.contains("framework") || tag.contains("library") || tag == "api"
                || tag == "core" || tag == "mcm" {
                return .framework
            }
        }

        // Visual / cosmetic
        for tag in lowered {
            if tag.contains("cosmetic") || tag.contains("visual") || tag.contains("appearance")
                || tag.contains("hair") || tag.contains("head") || tag.contains("tattoo")
                || tag.contains("eye") || tag.contains("body") || tag.contains("face")
                || tag.contains("dye") || tag.contains("texture") || tag.contains("portrait")
                || tag.contains("skin") || tag.contains("outfit") || tag.contains("clothing")
                || tag.contains("accessory") || tag.contains("horn") || tag.contains("tail")
                || tag.contains("wing") || tag.contains("beard") || tag.contains("model") {
                return .visual
            }
        }

        // Content extensions
        for tag in lowered {
            if tag.contains("class") || tag.contains("subclass") || tag.contains("spell")
                || tag.contains("feat") || tag.contains("race") || tag.contains("background")
                || tag.contains("metamagic") || tag.contains("cantrip") || tag.contains("origin")
                || tag.contains("companion") || tag.contains("multiclass") || tag.contains("ability")
                || tag.contains("warlock") || tag.contains("sorcerer") || tag.contains("barbarian")
                || tag.contains("ranger") || tag.contains("cleric") || tag.contains("paladin")
                || tag.contains("bard") || tag.contains("wizard") || tag.contains("rogue")
                || tag.contains("druid") || tag.contains("fighter") || tag.contains("monk") {
                return .contentExtension
            }
        }

        // Gameplay
        for tag in lowered {
            if tag.contains("gameplay") || tag.contains("fix") || tag.contains("balance")
                || tag.contains("tweak") || tag.contains("qol") || tag.contains("item")
                || tag.contains("equipment") || tag.contains("armor") || tag.contains("weapon")
                || tag.contains("camp") || tag.contains("inventory") || tag.contains("difficulty")
                || tag.contains("respec") || tag.contains("travel") || tag.contains("merchant")
                || tag.contains("gold") || tag.contains("rest") || tag.contains("party")
                || tag.contains("ai") {
                return .gameplay
            }
        }

        return nil
    }

    // MARK: - Name Heuristics

    private func inferFromName(_ name: String) -> ModCategory? {
        let lowered = name.lowercased()

        // Late loaders — check first (most specific)
        let latePatterns = [
            "compatibility framework", "spell list combiner", "compat patch",
            "compatibility patch", " cf ", "patches for ",
            "action resource combiner", "progressions combiner",
            "container combiner", "list combiner",
        ]
        for pattern in latePatterns {
            if lowered.contains(pattern) { return .lateLoader }
        }
        // Name ending with " patch" or " patches" when it references another mod
        if (lowered.hasSuffix(" patch") || lowered.hasSuffix(" patches"))
            && lowered.count > 10 {
            return .lateLoader
        }

        // Frameworks
        let frameworkPatterns = [
            "community library", "improvedui", "impui", "5espells",
            "unlock level curve", "mod configuration menu", "mcm",
            "vlad's grimoire", "vladsgrimoire", "script extender",
            "native mod loader", "mod fixer", "bg3se",
            "volition cabinet", "communitylib", "shared library",
            "configuration framework", "party limit begone",
        ]
        for pattern in frameworkPatterns {
            if lowered.contains(pattern) { return .framework }
        }

        // Content extensions (classes, subclasses, spells, D&D archetypes)
        let contentPatterns = [
            "subclass", "new class", "extra spell", "featsextra",
            "metamagic extended", "wild magic d100", "expansion",
            "additional spell", "new race",
            "warlock patron", "sorcerer origin", "barbarian path",
            "ranger archetype", "cleric domain", "paladin oath",
            "bard college", "wizard school", "rogue archetype",
            "druid circle", "fighter archetype", "monk way",
            "feat expansion", "spell expansion",
        ]
        for pattern in contentPatterns {
            if lowered.contains(pattern) { return .contentExtension }
        }

        // Visual / cosmetic
        let visualPatterns = [
            "hair", "cosmetic", "appearance", "portrait", "eyes",
            "skin", "tattoo", "body mod", "head mod", "dye",
            "visual overhaul", "reshade", "hairstyle", "outfit",
            "clothing", "custom head", "eye color", "piercing",
            "makeup", "scar", "horn", "tail",
        ]
        for pattern in visualPatterns {
            if lowered.contains(pattern) { return .visual }
        }

        // Gameplay
        let gameplayPatterns = [
            "camp event", "long rest", "fast travel", "better ai",
            "party size", "party limit", "carry weight", "auto loot",
            "starting equipment", "respec", "difficulty",
            "gold", "trader", "merchant",
        ]
        for pattern in gameplayPatterns {
            if lowered.contains(pattern) { return .gameplay }
        }

        return nil
    }
}
