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

### Phase 2: Conflict Detection [DONE]

Parse the `<Conflicts>` node from `meta.lsx` and warn when conflicting mods are both active.

**Modified files:**
- `Models/ModInfo.swift` — added `conflicts: [ModDependency]` field
- `Models/ModWarning.swift` — added `.conflictingMods` warning category
- `Services/ModDiscoveryService.swift` — parses `<Conflicts>` node from meta.lsx alongside dependencies
- `Services/ModValidationService.swift` — added `checkConflictingMods()` with deduplicated pair detection
- `Views/ModDetailView.swift` — added "Declared Conflicts" section showing conflict status per mod
- `Views/ModListView.swift` — added "Deactivate" action button for conflict warnings in the banner
- `Views/ModRowView.swift` — added tooltips for SE badge and no-metadata label

### Phase 3: Game Compatibility (P1) [DONE]

- **ModCrashSanityCheck workaround**: auto-delete the problematic directory on launch and before save
- **Last-exported order recovery**: detect external modsettings.lsx changes via SHA-256 hash and prompt restore from backup
- **Import from save files**: extract modsettings.lsx from .lsv archives via PakReader

**Modified files:**
- `Utilities/FileLocations.swift` — added `modCrashSanityCheckFolder`, `lastExportHashFile`, `modCrashSanityCheckExists`
- `Models/ModWarning.swift` — added `.modCrashSanityCheck` and `.externalModSettingsChange` categories, `.deleteModCrashSanityCheck` and `.restoreModSettings` suggested actions
- `Services/ModValidationService.swift` — added `checkModCrashSanityCheck()` validation check
- `App/AppState.swift` — added `deleteModCrashSanityCheckIfNeeded()`, `recordModSettingsHash()`, `checkForExternalModSettingsChange()`, `restoreFromLatestBackup()`, `importFromSaveFile(url:)`, `showExternalChangeAlert` state
- `App/BG3MacModManagerApp.swift` — added "Import from Save File..." menu item (Cmd+Shift+I) with save file picker
- `Views/ModListView.swift` — added "Delete Folder" and "Restore Backup" action buttons in warnings banner
- `Views/ContentView.swift` — added external modsettings.lsx change detection alert dialog

### Phase 4: Enhanced UX (P2) [DONE]

- Inline dependency status indicators on mod rows (link icon with red/yellow/green states)
- Transitive dependency tree visualization (depth-first tree in detail panel)
- "Activate Missing Dependencies" one-click action (per-mod button + global menu item + per-warning button)
- Multi-select drag-and-drop (Cmd+Click/Shift+Click, cross-pane drag, multi-select action bar, group context menus)

### Phase 5: Drag-and-Drop Install, SE Warning, Heuristics (P3)

- Drag-and-drop mod installation from Finder (window-level drop target, batch import, post-import activation prompt)
- Script Extender disappearance warning (persist deployed state, warn when SE goes missing after a game update)
- Category inference heuristics expansion (removed UUID database, expanded tag/name pattern matching)

**Modified files:**
- `App/AppState.swift` — added `isImporting`, `lastImportedMods`, `showImportActivation`, `navigateToSidebarItem`; new `importMods(from:)` batch method; updated `importArchive()` to return replaced filenames; SE state persistence in `refreshSEStatus()`; SE flag in `runValidation()` and `saveModSettings()`
- `Views/ContentView.swift` — added window-level `.onDrop()` with drop target overlay, importing progress indicator, post-import activation alert, sidebar navigation via `navigateToSidebarItem`
- `App/BG3MacModManagerApp.swift` — updated `importModFromPanel()` to use batch `importMods(from:)`
- `Utilities/FileLocations.swift` — added `seDeployedFlagFile`
- `Services/ScriptExtenderService.swift` — added `recordDeployed()`, `clearDeployedFlag()`, `wasDeployed()` persistence
- `Models/ModWarning.swift` — added `.seDisappeared` category, `.viewSEStatus` suggested action
- `Services/ModValidationService.swift` — added `seWasPreviouslyDeployed` parameter to `validate()`/`validateForSave()`, added `checkSEDisappeared()` check
- `Views/ModListView.swift` — added "View SE Status" action button for SE disappearance warning
- `Services/CategoryInferenceService.swift` — removed `knownMods` UUID database, expanded tag heuristics (~30 new keywords), expanded name heuristics (~30 new patterns), added gameplay name patterns

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
- `CategoryInferenceService` with 3-layer inference: user overrides → tag heuristics → name heuristics
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

### 6. Enhanced Dependency Visualization [Phase 4 - DONE]

**Implemented:**
- **Inline dependency icons on ModRowView**: compact link icon for active mods with dependencies
  - Red `link.badge.plus` = missing dependencies
  - Yellow `arrow.up.arrow.down` = dependency load order issue
  - Green `link` = all dependencies satisfied and in correct order
- **Transitive dependency tree in ModDetailView**: depth-first tree view with indentation
  - Shows nested dependencies from direct deps → their deps → etc.
  - Each node shows active/inactive status and position in load order
  - Only displayed when there are nested (depth > 0) transitive deps
- **"Activate Missing Dependencies" action** (three entry points):
  - Per-mod button in ModDetailView dependencies section header
  - Global menu item in active mods ellipsis menu
  - Per-warning "Activate Deps" button in warnings banner
  - Inserts activated deps before the dependent mod for correct load order
  - Iterates transitively until all activatable deps are resolved
- **New `activateDependencies` suggested action** in ModWarning for deps available in inactive list
- **Helper methods in AppState**: `hasMissingDependencies()`, `hasDependencyOrderIssue()`,
  `transitiveDependencies()`, `activateMissingDependencies(for:)`, `activateAllMissingDependencies()`

**Modified files:**
- `App/AppState.swift` — dependency helpers, multi-select state, activate/deactivate missing deps
- `Models/ModWarning.swift` — added `.activateDependencies(modUUID:)` suggested action
- `Services/ModValidationService.swift` — smarter missing dep warnings (distinguish activatable vs not installed)
- `Views/ModRowView.swift` — inline dependency status icon
- `Views/ModDetailView.swift` — "Activate Missing" button, transitive dependency tree

### 7. Drag-and-Drop Improvements [Phase 4 - DONE]

**Implemented:**
- **Multi-select**: `List(selection:)` now binds to `Set<String>` (`selectedModIDs`) enabling native
  Cmd+Click and Shift+Click multi-selection in both active and inactive lists
- **Multi-select action bar**: appears when 2+ mods selected, shows count and bulk Activate/Deactivate buttons
- **Multi-select detail panel**: when 2+ mods selected, detail panel shows selection summary
- **Group context menus**: right-click shows "Deactivate N Selected" / "Activate N Selected" options
- **Cross-pane drag**: `.draggable(mod.uuid)` on each row + `.dropDestination(for: String.self)` on each list
  - Drag from inactive → active list = activate
  - Drag from active → inactive list = deactivate
  - Visual drop targeting border (green for active, gray for inactive)
- **Group drag within active list**: `.onMove` works with the Set<String> selection for moving multiple items
- **Selection sync**: `onChange(of: selectedModIDs)` keeps `selectedModID` in sync for detail panel

**Modified files:**
- `App/AppState.swift` — `selectedModIDs: Set<String>`, `activateSelectedMods()`, `deactivateSelectedMods()`,
  `moveSelectedActiveMods(to:)`, updated `selectedMod` computed property
- `Views/ModListView.swift` — multi-select lists, action bar, cross-pane drag-drop, multi-select detail panel

### 8. Drag-and-Drop Install [Phase 5 - DONE]

**Implemented:**
- **Window-level drag-and-drop from Finder**: Drop `.pak`, `.zip`, `.tar` (and variants) onto the app window
  - Visual drop target overlay with accent color border and "Drop to Import Mods" label
  - Progress indicator in status bar during import
- **Batch import**: Multiple files processed in one operation with a single post-import prompt
- **Post-import activation prompt**: Alert asks "Activate All" or "Keep Inactive" after importing new mods
- **Duplicate detection**: Reports when existing PAK files are replaced during import
- **Cmd+I multi-select**: File picker now batches all selected files through same code path

### 9. Script Extender Disappearance Warning [Phase 5 - DONE]

**Implemented:**
- **SE deployment state persistence**: Records when SE is detected as deployed (`se_was_deployed.json`)
- **Disappearance detection**: On refresh/validation, warns if SE was previously deployed but is now missing
- **"View SE Status" action button**: Navigates to the Script Extender sidebar tab for re-deployment
- **No false positives**: Users who never had SE installed won't see the warning

### 10. Category Heuristics Expansion [Phase 5 - DONE]

**Implemented:**
- **Removed UUID database**: Eliminated the 2-entry `knownMods` dictionary in favor of pure heuristics
- **Expanded tag heuristics**: Added ~30 new keywords across all tiers (D&D class names, outfit/clothing,
  camp/inventory, horn/tail/wing, etc.)
- **Expanded name heuristics**: Added ~30 new patterns (D&D subclass archetypes like "warlock patron",
  "paladin oath"; combiner variants; gameplay patterns like "party size", "carry weight")
- **New gameplay name patterns**: Previously missing from `inferFromName()` — now covers camp events,
  fast travel, difficulty, auto loot, merchants, etc.
