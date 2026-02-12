import Foundation

/// Infers a ModCategory for mods using a known-mods database, tag heuristics,
/// and name heuristics. Users can override inferred categories; overrides are
/// persisted to disk.
final class CategoryInferenceService {

    // MARK: - Public API

    /// Infer a category for a mod. Checks (in order):
    /// 1. User override (persisted)
    /// 2. Known-mods database (by UUID)
    /// 3. Tag-based heuristics
    /// 4. Name-based heuristics
    /// Returns nil if no category can be inferred (mod stays unsorted).
    func inferCategory(for mod: ModInfo) -> ModCategory? {
        if let override = userOverrides[mod.uuid] {
            return override
        }
        if let known = Self.knownMods[mod.uuid] {
            return known
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
            if tag.contains("framework") || tag.contains("library") || tag == "api" {
                return .framework
            }
        }

        // Visual / cosmetic
        for tag in lowered {
            if tag.contains("cosmetic") || tag.contains("visual") || tag.contains("appearance")
                || tag.contains("hair") || tag.contains("head") || tag.contains("tattoo")
                || tag.contains("eye") || tag.contains("body") || tag.contains("face")
                || tag.contains("dye") || tag.contains("texture") {
                return .visual
            }
        }

        // Content extensions
        for tag in lowered {
            if tag.contains("class") || tag.contains("subclass") || tag.contains("spell")
                || tag.contains("feat") || tag.contains("race") || tag.contains("background")
                || tag.contains("metamagic") || tag.contains("cantrip") {
                return .contentExtension
            }
        }

        // Gameplay
        for tag in lowered {
            if tag.contains("gameplay") || tag.contains("fix") || tag.contains("balance")
                || tag.contains("tweak") || tag.contains("qol") || tag.contains("item")
                || tag.contains("equipment") || tag.contains("armor") || tag.contains("weapon") {
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
            "compatibility patch", " cf ", "patches for "
        ]
        for pattern in latePatterns {
            if lowered.contains(pattern) { return .lateLoader }
        }
        // Name ending with " patch" or " fix" when it also references another mod
        if (lowered.hasSuffix(" patch") || lowered.hasSuffix(" patches"))
            && lowered.count > 10 {
            return .lateLoader
        }

        // Frameworks
        let frameworkPatterns = [
            "community library", "improvedui", "impui", "5espells",
            "unlock level curve", "mod configuration menu", "mcm",
            "vlad's grimoire", "vladsgrimoire", "script extender",
            "native mod loader", "mod fixer", "bg3se"
        ]
        for pattern in frameworkPatterns {
            if lowered.contains(pattern) { return .framework }
        }

        // Content extensions (classes, subclasses, spells)
        let contentPatterns = [
            "subclass", "new class", "extra spell", "featsextra",
            "metamagic extended", "wild magic d100", "expansion",
            "additional spell", "new race"
        ]
        for pattern in contentPatterns {
            if lowered.contains(pattern) { return .contentExtension }
        }

        // Visual / cosmetic
        let visualPatterns = [
            "hair", "cosmetic", "appearance", "portrait", "eyes",
            "skin", "tattoo", "body mod", "head mod", "dye",
            "visual overhaul", "reshade"
        ]
        for pattern in visualPatterns {
            if lowered.contains(pattern) { return .visual }
        }

        return nil
    }

    // MARK: - Known Mods Database
    //
    // UUIDs for popular BG3 mods mapped to their canonical load-order tier.
    // Sourced from the BG3 Modding Community Wiki's general load order guide.

    // Known UUIDs are populated as users encounter popular mods.
    // The tag-based and name-based heuristics serve as the primary inference
    // mechanism so the known-mods list does not need to be exhaustive.
    //
    // To add a mod: find its UUID in meta.lsx, add it to the appropriate tier below.
    static let knownMods: [String: ModCategory] = {
        var db: [String: ModCategory] = [:]

        // ── Tier 1: Frameworks ──────────────────────────────────────────
        // Mods here are well-known libraries/frameworks that should always load first.
        // UUIDs verified from Nexus Mods or mod author pages where possible.
        let frameworks: [String] = [
            // Mod Configuration Menu (MCM)
            "755a8a72-407f-4f0d-9a33-274ac0f5b45d",
        ]
        for uuid in frameworks { db[uuid] = .framework }

        // ── Tier 5: Late Loaders ────────────────────────────────────────
        let lateLoaders: [String] = [
            // Compatibility Framework
            "67bbb2ec-4900-4aaf-af8d-e2d3fbc47bd8",
        ]
        for uuid in lateLoaders { db[uuid] = .lateLoader }

        return db
    }()
}
