# Load Order Sorting Improvements Plan

## Phases

### Phase 1: Category-Aware Smart Sort [DONE]

Full implementation of tiered load order sorting.

**New files:**
- `Models/ModCategory.swift` — 5-tier enum (Framework, Gameplay, Content, Visual, Late Loader)
- `Services/CategoryInferenceService.swift` — inference via known-mods DB, tag heuristics, name heuristics, with persisted user overrides

**Modified files:**
- `Models/ModInfo.swift` — added `category: ModCategory?` field
- `App/AppState.swift` — added `smartSort()`, `setCategoryOverride()`, `inferCategory()`, integrated `CategoryInferenceService`
- `Views/ModListView.swift` — added Smart Sort button, updated menu with both sort options
- `Views/ModRowView.swift` — added colored tier badge pills next to mod names
- `Views/ModDetailView.swift` — added category section with picker for user overrides

### Phase 2: Conflict Detection (P0)

Parse the `<Conflicts>` node from `meta.lsx` and warn when conflicting mods are both active.

- Add `conflicts: [ModDependency]` to `ModInfo`
- Parse Conflicts in `ModDiscoveryService.parseMetaLsx()`
- Add `.conflictingMods` category to `ModWarning`
- Add `checkConflictingMods()` to `ModValidationService`

### Phase 3: Game Compatibility (P1)

- **ModCrashSanityCheck workaround**: auto-delete the problematic directory on launch
- **Last-exported order recovery**: detect external modsettings.lsx changes and prompt restore
- **Import from save files**: extract modsettings.lsx from .lsv archives

### Phase 4: Enhanced UX (P2)

- Inline dependency status indicators on mod rows
- Transitive dependency tree visualization
- "Activate Missing Dependencies" one-click action
- Multi-select drag-and-drop

### Phase 5: Community Features (P3)

- Import load order from text/URL
- Community preset load orders

---

## Current State

The app already has solid foundations:
- Topological sort via Kahn's algorithm for dependency-based ordering
- Manual drag-and-drop reordering
- Validation warnings for wrong load order, missing deps, circular deps
- Profile save/load system
- Auto-backup before modsettings.lsx writes

However, compared to the Windows BG3 Mod Manager (BG3MM by LaughingLeader) and
community tooling, there are several meaningful improvements to make — especially
around **smart load order sorting** that goes beyond raw dependency resolution.

---

## Detailed Feature Descriptions

### 1. Category-Aware Smart Sort [Phase 1 - DONE]

**Problem:** The current `autoSortByDependencies()` only considers declared
dependencies. Many mods don't declare dependencies at all, yet the community has
a well-established 5-tier load order convention that most players follow manually.

**Solution:** Implemented a tiered sorting system that combines dependency resolution
with category awareness:

- **Tier 1 — Frameworks & Libraries** (load first): ImpUI, Community Library,
  5eSpells, Unlock Level Curve, MCM, Vlad's Grimoire, Script Extender mods
- **Tier 2 — Gameplay/Fix Mods**: action mods, item mods, bug fixes
- **Tier 3 — Content Extensions**: class mods, feature extensions, subclass mods
- **Tier 4 — Visual/Cosmetic Mods**: appearance, texture, UI mods
- **Tier 5 — Late Loaders/Patches** (load last): Compatibility Framework,
  Spell List Combiner, patch mods

**Implementation:**
- `ModCategory` enum with 5 tiers, each with display name, color, and icon
- `CategoryInferenceService` with 4-layer inference: user overrides → known-mods DB → tag heuristics → name heuristics
- User overrides persisted to `~/Library/Application Support/BG3MacModManager/category_overrides.json`
- `smartSort()` groups by tier, applies topological sort within each tier
- Uncategorized mods sort with Tier 3 (content extensions) as a safe middle ground

### 2. Conflict Detection from Mod Metadata [Phase 2]

**Problem:** The app doesn't read the `Conflicts` node from `meta.lsx`. BG3MM
shows conflicts in tooltips; our app currently only checks for duplicate UUIDs.

**Solution:**
- Extend `ModDiscoveryService` to parse `<Conflicts>` node from `meta.lsx`
- Add `conflicts: [ModDependency]` field to `ModInfo`
- Add validation check: warn when two active mods declare each other as conflicts
- Severity: **Warning** (not critical)

### 3. ModCrashSanityCheck Workaround [Phase 3]

**Problem:** Since Patch 8, a directory at
`~/Documents/Larian Studios/Baldur's Gate 3/ModCrashSanityCheck` can cause the
game to deactivate externally-managed mods. BG3MM auto-deletes this folder.

**Solution:**
- Check for existence on app launch and before exporting load order
- Auto-delete with explanation
- Add as **Info** validation warning when detected

### 4. Import Load Order from Save Files [Phase 3]

**Problem:** BG3MM can extract mod load order from save game files. Our app cannot.

**Solution:**
- BG3 save files (`.lsv`) are LSPK archives containing `modsettings.lsx`
- Reuse existing `PakReader` to extract, `ModSettingsService.read()` to parse
- Add "Import from Save File..." menu item

### 5. Last-Exported Order Recovery [Phase 3]

**Problem:** If the game resets `modsettings.lsx`, users lose their load order.

**Solution:**
- Detect on launch: compare modsettings.lsx against last known export
- Prompt to restore from auto-backup if they differ

### 6. Enhanced Dependency Visualization [Phase 4]

- Inline dependency status icons on mod rows
- Transitive dependency tree in detail panel
- "Activate Missing Dependencies" action

### 7. Drag-and-Drop Improvements [Phase 4]

- Multi-select (Cmd+Click, Shift+Click)
- Group drag
- Cross-pane drag with position targeting

### 8. Load Order Sharing [Phase 5]

- Import from text/URL
- Community preset load orders
