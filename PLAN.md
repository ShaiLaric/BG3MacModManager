# Load Order Sorting Improvements Plan

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

## Proposed Improvements (Priority Order)

### 1. Category-Aware Smart Sort

**Problem:** The current `autoSortByDependencies()` only considers declared
dependencies. Many mods don't declare dependencies at all, yet the community has
a well-established 5-tier load order convention that most players follow manually.

**Solution:** Implement a tiered sorting system that combines dependency resolution
with category awareness:

- **Tier 1 — Frameworks & Libraries** (load first): ImpUI, Community Library,
  5eSpells, Unlock Level Curve, MCM, Vlad's Grimoire, Script Extender mods
- **Tier 2 — Gameplay/Fix Mods**: action mods, item mods, bug fixes
- **Tier 3 — Content Extensions**: class mods, feature extensions, subclass mods
- **Tier 4 — Visual/Cosmetic Mods**: appearance, texture, UI mods
- **Tier 5 — Late Loaders/Patches** (load last): Compatibility Framework,
  Spell List Combiner, patch mods

**Implementation:**
- Add a `ModCategory` enum with these 5 tiers
- Build a **known-mods database** (embedded JSON/plist) mapping well-known mod
  UUIDs to their canonical tier (e.g., ImpUI → Tier 1, Compatibility Framework → Tier 5)
- Use **tag-based heuristics** to infer category for unknown mods:
  - Tags containing "Framework", "Library" → Tier 1
  - Tags containing "Fix", "Gameplay" → Tier 2
  - Tags containing "Class", "Subclass", "Spell" → Tier 3
  - Tags containing "Cosmetic", "Visual", "Hair", "Appearance" → Tier 4
  - Tags containing "Patch", "Compatibility" → Tier 5
- Use **name-based heuristics** as fallback (e.g., mod name contains "Patch" or
  "Compatibility" → Tier 5)
- Allow users to **manually assign/override** a mod's category via the detail panel
- Persist user category overrides in app storage
- Sort algorithm: within each tier, apply topological dependency sort; across
  tiers, enforce tier ordering

**New UI:**
- Add "Smart Sort" button alongside existing "Sort by Dependencies"
- Show tier badges/labels on mod rows (colored pill: "Framework", "Gameplay", etc.)
- Add category column or grouping headers in the active mods list

### 2. Conflict Detection from Mod Metadata

**Problem:** The app doesn't read the `Conflicts` node from `meta.lsx`. BG3MM
shows conflicts in tooltips; our app currently only checks for duplicate UUIDs.

**Solution:**
- Extend `PakReader` / `ModDiscoveryService` to parse the `<Conflicts>` node
  from `meta.lsx` (same structure as `<Dependencies>`)
- Add a `conflicts: [ModDependency]` field to `ModInfo`
- Add a new validation check in `ModValidationService`: warn when two active mods
  declare each other as conflicts
- Show conflict warnings in the warnings banner and mod detail panel
- Severity: **Warning** (not critical — let users override if they know what
  they're doing)

### 3. ModCrashSanityCheck Workaround

**Problem:** Since Patch 8, a directory at
`~/Library/Application Support/Baldur's Gate 3/ModCrashSanityCheck` (or the
macOS equivalent path) can cause the game to deactivate externally-managed mods.
BG3MM auto-deletes this folder.

**Solution:**
- Check for the existence of this directory on app launch and before exporting
  load order
- Auto-delete it (or prompt the user) with an explanation of why
- Add this to the validation system as an **Info** warning when detected

### 4. Import Load Order from Save Files

**Problem:** BG3MM can extract mod load order from save game files. Our app
cannot. This is useful when a user's modsettings.lsx gets reset but their save
still has the correct order.

**Solution:**
- BG3 save files (`.lsv`) are LSPK archives containing a `modsettings.lsx`
- Reuse existing `PakReader` to extract `modsettings.lsx` from the save
- Parse it with existing `ModSettingsService.read()`
- Present the extracted order and let the user apply it
- Add "Import from Save File..." menu item

### 5. Last-Exported Order Recovery

**Problem:** If the game or another tool resets `modsettings.lsx`, users lose
their load order. BG3MM saves a `LastExported.json` and prompts to restore it.

**Solution:**
- The app already has auto-backup, which partially addresses this
- Add detection on launch: compare current modsettings.lsx against the last
  known export
- If they differ (and the app didn't make the change), show a warning:
  "Your load order appears to have been modified externally. Restore from
  last backup?"
- This leverages the existing backup system but adds proactive detection

### 6. Enhanced Dependency Visualization

**Problem:** Dependencies are shown in the detail panel but not inline in the
mod list. Missing dependencies require navigating to each mod's detail view.

**Solution:**
- Show dependency status inline on mod rows (small icon: green checkmark if all
  deps satisfied, red X if any missing)
- Add "dependency chain" visualization in detail panel: show the full transitive
  dependency tree, not just direct dependencies
- When hovering/clicking a dependency, highlight it in the active mods list
- Add "Activate Missing Dependencies" suggested action that auto-activates
  required mods from the inactive list

### 7. Drag-and-Drop Improvements

**Problem:** Current drag-and-drop works for single mods. BG3MM supports
multi-select drag and cross-pane drag (inactive → active with position).

**Solution:**
- Support multi-select in the mod list (Cmd+Click, Shift+Click)
- Allow dragging selected group as a unit
- Support dragging from inactive list directly into a position in the active list
- Show insertion indicator (line between mods) during drag

### 8. Load Order Sharing & Community Presets

**Problem:** Users frequently share load orders on Reddit/Discord as text lists.
The app supports text export but not easy import of shared orders.

**Solution:**
- "Import Load Order from Text" — parse a pasted list of mod names/UUIDs and
  attempt to match against installed mods, reordering accordingly
- "Import from URL" — fetch and parse a shared load order from a pastebin/gist
- Community preset load orders (curated lists for popular mod combinations)

---

## Implementation Priority

| # | Feature | Impact | Effort | Priority |
|---|---------|--------|--------|----------|
| 1 | Category-Aware Smart Sort | High | Medium | P0 |
| 2 | Conflict Detection | High | Low | P0 |
| 3 | ModCrashSanityCheck Workaround | Medium | Low | P1 |
| 4 | Import from Save Files | Medium | Medium | P1 |
| 5 | Last-Exported Order Recovery | Medium | Low | P1 |
| 6 | Enhanced Dependency Visualization | Medium | Medium | P2 |
| 7 | Drag-and-Drop Multi-Select | Low | Medium | P2 |
| 8 | Load Order Sharing | Low | High | P3 |

---

## Files to Modify

### For Category-Aware Smart Sort (P0):
- **New:** `Models/ModCategory.swift` — enum + known-mods database
- **Modify:** `Models/ModInfo.swift` — add `category` field
- **Modify:** `Services/ModValidationService.swift` — category inference logic
- **Modify:** `App/AppState.swift` — new `smartSort()` method
- **Modify:** `Views/ModListView.swift` — Smart Sort button, tier badges
- **Modify:** `Views/ModRowView.swift` — category pill/badge display
- **New:** `Resources/known_mods.json` — UUID-to-category mapping

### For Conflict Detection (P0):
- **Modify:** `Models/ModInfo.swift` — add `conflicts` field
- **Modify:** `Services/ModDiscoveryService.swift` — parse Conflicts node
- **Modify:** `Services/PakReader.swift` — extract Conflicts from meta.lsx
- **Modify:** `Services/ModValidationService.swift` — conflict check
- **Modify:** `Models/ModWarning.swift` — new `.conflictingMods` category

### For ModCrashSanityCheck (P1):
- **Modify:** `App/AppState.swift` — check on launch
- **Modify:** `Utilities/FilePathHelper.swift` — path constant
- **Modify:** `Services/ModValidationService.swift` — validation check

### For Import from Save (P1):
- **Modify:** `Services/ModSettingsService.swift` — extract from .lsv
- **Modify:** `Views/ModListView.swift` — menu item
- **Modify:** `App/AppState.swift` — import action

### For Last-Exported Recovery (P1):
- **Modify:** `App/AppState.swift` — detect external changes on launch
- **Modify:** `Services/BackupService.swift` — compare logic
