# CLAUDE.md

## Project Overview

BG3 Mac Mod Manager is a macOS SwiftUI application for managing Baldur's Gate 3 mods. It uses Swift Package Manager (SPM) with swift-tools-version 5.9, targeting macOS 13+. Current release: **v1.2.1**.

## Build Environment

**Do not attempt `swift build`, `swift test`, or any Swift toolchain commands.** The CI/CD environment does not have Swift installed. Verify correctness by reading code and checking that changes follow existing patterns.

## Project Structure

```
Sources/BG3MacModManager/
  App/          - App entry point (BG3MacModManagerApp), AppState
  Models/       - Data models (ModModel, ModCategory, NexusUpdateInfo, etc.)
  Services/     - Business logic (ModService, LaunchService, ModNotesService, NexusAPIService, NexusURLImportService, etc.)
  Utilities/    - Helpers (FileLocations, etc.)
  Views/        - SwiftUI views (ContentView, ModListView, ModFilePickerView, NexusURLImportView, etc.)
Tests/BG3MacModManagerTests/
  TestHelpers.swift            - Factory functions (makeModInfo, makeDependency, makeSEStatus)
  Version64Tests.swift         - Version64 model tests
  ModInfoTests.swift           - ModInfo model, factories, MetadataSource, Constants
  DataBinaryReadingTests.swift - Data extension binary reading (UInt16/32/64, Int64)
  ModCategoryTests.swift       - ModCategory enum ordering, Codable, CaseIterable
  TextExportServiceTests.swift - CSV/Markdown/plain text export
  CategoryInferenceServiceTests.swift - Tag/name heuristics, overrides
  ModValidationServiceTests.swift     - All 10 validation checks, topological sort
  LoadOrderImportServiceTests.swift   - BG3MM JSON & LSX import parsing
  PakReaderTests.swift                - Binary format errors, CompressionType
  ModNotesServiceTests.swift          - Per-mod notes persistence
  NexusURLImportServiceTests.swift    - CSV/JSON/TXT import parsing, mod matching
  NexusAPIServiceTests.swift          - Mod ID extraction, update result logic, cache encoding
```

## Key Patterns

- **Icons**: SF Symbols only — no custom image assets
- **Button styles**: `.borderedProminent` for primary actions, `.bordered` for secondary, `.plain` for icon-only
- **Toolbar**: Standard macOS toolbar in ContentView; in-content action bars in views like ModListView for prominent buttons
- **All buttons** should have `.help()` tooltips
- **Help & tooltips**: Any changes or new features must update `HelpView.swift` documentation and ensure all new buttons/controls have `.help()` tooltips
- **State**: Single `AppState` (ObservableObject) passed via `.environmentObject()`
- **Async**: Use `Task { await ... }` in button actions for async AppState methods

## Workflow

**Ask clarifying questions when uncertain.** If a prompt is ambiguous, has multiple possible interpretations, or you're unsure about the intended UX or behavior, ask the user before implementing. It is always better to clarify upfront than to implement the wrong thing and iterate.

**Always update CLAUDE.md when finishing updates.** After implementing a backlog item or making significant changes, mark the item as done in the Backlog section and update any affected documentation (project structure, key patterns, etc.) before committing.

**Before every `git push`, ask the user what version number to use** and update `CFBundleShortVersionString` in `Sources/BG3MacModManager/Info.plist` accordingly. Do not push without confirming the version.

## Dependencies

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (>=0.9.19) — ZIP archive handling

## Backlog

Prioritized feature and UX improvements organized by tier. Each item includes a scope tag (S/M/L) and the key files that need changes.

### Tier 1: Quick Wins

| # | Title | Scope | Status | Description | Key Files |
|---|-------|-------|--------|-------------|-----------|
| 1.1 | Unsaved Changes Indicator | S | **Done** | Track dirty state when load order is mutated; show indicator on Save button. Prevents silently losing work. | `AppState.swift`, `ModListView.swift` |
| 1.2 | Sidebar Mod Count Badges | S | **Done** | `.badge()` on sidebar items: warning count on Mods, profile count, backup count. | `ContentView.swift` |
| 1.3 | Keyboard Shortcuts | S | **Done** | Cmd+Shift+E (export ZIP), Cmd+Delete (deactivate selected), Cmd+Shift+G (launch game). Updated HelpView. | `BG3MacModManagerApp.swift`, `HelpView.swift` |
| 1.4 | Category Filter Chips | S | **Done** | Toggleable filter row (Framework/Gameplay/Content/Visual/Late Loader/Uncategorized) above mod lists for users with 100+ mods. | `ModListView.swift` |
| 1.5 | Mod Description Preview in Row | S | **Done** | Show single-line truncated `modDescription` beneath author/version in `ModRowView` for at-a-glance context. | `ModRowView.swift` |
| 1.6 | Confirm on Close with Unsaved Changes | S | **Done** | Standard macOS "Save changes?" dialog on window close when dirty state is true. Depends on 1.1. | `BG3MacModManagerApp.swift` |
| 1.7 | Reveal in Finder from Context Menu | S | **Done** | Add "Reveal in Finder" to mod row context menus via `NSWorkspace.shared.activateFileViewerSelecting()`. | `ModListView.swift` |
| 1.8 | Persistent Mod Count in Status Bar | S | **Done** | "N active / M inactive" in the bottom status bar as an always-visible summary. | `ContentView.swift` |

### Tier 2: Medium Features

| # | Title | Scope | Status | Description | Key Files |
|---|-------|-------|--------|-------------|-----------|
| 2.1 | Undo/Redo for Load Order | M | **Done** | Snapshot `(activeMods, inactiveMods)` before each mutation; support Cmd+Z / Cmd+Shift+Z. | `AppState.swift`, `BG3MacModManagerApp.swift` |
| 2.2 | Profile Load Missing Mods Report | M | **Done** | When loading a profile, show a summary dialog of matched vs. missing mods with Nexus URLs. Reuse `ImportSummaryView`. | `AppState.swift`, `ContentView.swift`, `ImportSummaryView.swift` |
| 2.3 | Inactive Mods Sorting Options | S–M | **Done** | Sort picker for inactive section: by name, author, category, file date, or file size. Persistent via @AppStorage. | `ModListView.swift` |
| 2.4 | PAK Inspector Tool | M | **Done** | New tool under "Tools" sidebar to inspect any PAK or ZIP file's internal listing, meta.lsx, and info.json. Accepts ZIP archives containing PAKs with multi-PAK picker and ZIP-level info.json viewing. Uses custom `ModFilePickerView` for ZIP-as-file selection (bypasses macOS NSOpenPanel ZIP navigation), existing `PakReader` and `ArchiveService`. | `PakInspectorView.swift`, `ModFilePickerView.swift`, `ContentView.swift`, `PakReader.swift` |
| 2.5 | Positional Drag from Inactive to Active | M | **Done** | Dragging an inactive mod into the active list inserts at the drop position via `.onInsert`. Falls back to append when filters are active. | `ModListView.swift`, `AppState.swift` |
| 2.6 | Advanced Filter Popover | M | **Done** | Filter button in category bar with popover for: SE required, has warnings, metadata source. Badge shows active filter count. | `ModListView.swift` |
| 2.7 | Profile Renaming and Updating | M | **Done** | "Rename" and "Update" (overwrite with current load order) actions on profile rows. | `ProfileManagerView.swift`, `ProfileService.swift`, `AppState.swift` |
| 2.8 | Auto-save on Launch / Profile Load | S–M | **Done** | Settings toggles: "Auto-save before launching game" and "Save on profile load". `launchGame()` is now async. | `SettingsView.swift`, `AppState.swift`, `ModListView.swift`, `BG3MacModManagerApp.swift` |
| 2.9 | Warnings Badge Outside Mods Tab | S | **Done** | Critical/warning count badge on "Mods" sidebar item (implemented as part of 1.2). | `ContentView.swift` |
| 2.10 | Double-Click to Toggle Active/Inactive | S | **Done** | Double-click a mod row to activate/deactivate, matching LaughingLeader's BG3MM convention. | `ModRowView.swift` |

### Tier 3: Larger Features

| # | Title | Scope | Status | Description | Key Files |
|---|-------|-------|--------|-------------|-----------|
| 3.1 | Operation History Panel | L | | Named undo stack with a History sidebar item ("Activated Mod X", "Smart Sorted", "Loaded Profile Y"). | `AppState.swift`, new `HistoryView.swift`, `ContentView.swift` |
| 3.2 | Nexus Mods Update Detection | L | **Done** | Query Nexus API to compare installed vs. latest versions; show "Update Available" badges. Requires API key in Settings. | `NexusAPIService.swift`, `NexusUpdateInfo.swift`, `SettingsView.swift`, `ModRowView.swift`, `ModDetailView.swift`, `ModListView.swift`, `ContentView.swift`, `AppState.swift` |
| 3.3 | Mod Groups / Collections | L | | User-defined named groups orthogonal to categories. Activate/deactivate/view entire groups. | New `ModGroup.swift`, new `ModGroupService.swift`, multiple views |
| 3.4 | Conflict Resolution Advisor | L | | Analyze conflict graph and suggest compatibility patches, load order adjustments, and Nexus search links. | New `ConflictAdvisorService.swift`, `ModListView.swift`, `ModDetailView.swift` |
| 3.5 | Comprehensive Test Suite | L | **Done** | ~150 tests across 11 test files + 1 helper: `ModInfoTests`, `DataBinaryReadingTests`, `ModCategoryTests`, `TextExportServiceTests`, `CategoryInferenceServiceTests`, `ModValidationServiceTests`, `LoadOrderImportServiceTests`, `PakReaderTests`, `ModNotesServiceTests`, `NexusURLImportServiceTests`, `NexusAPIServiceTests`. | `TestHelpers.swift`, multiple test files in `Tests/` |
| 3.6 | Per-Mod User Notes | M–L | **Done** | Editable notes per mod stored in app support JSON, editable from detail panel, icon indicator in row. | `ModNotesService.swift`, `ModDetailView.swift`, `ModRowView.swift`, `ModListView.swift`, `AppState.swift` |
| 3.7 | Bulk Nexus URL Import | M–L | **Done** | Import CSV/TSV/JSON/TXT files to bulk-populate Nexus URLs. Matches by UUID, exact name, or fuzzy name. | `NexusURLImportService.swift`, `NexusURLImportView.swift`, `NexusURLService.swift`, `ContentView.swift`, `AppState.swift` |

### Recommended Implementation Order

Items marked ~~strikethrough~~ are complete.

1. ~~**1.2 → 1.8 → 2.9** — Instant polish (sidebar badges, status bar count, warning badges)~~
2. ~~**1.1 + 1.6** — Unsaved changes indicator + close confirmation (core UX safety)~~
3. ~~**1.7 → 2.10** — Reveal in Finder, double-click toggle (standard conventions)~~
4. ~~**1.4 → 1.5**~~ ~~→ **1.3**~~ — ~~Category filters, description preview~~, ~~keyboard shortcuts~~
5. ~~**2.1** — Undo/Redo (safety feature, prerequisite for 3.1)~~
6. ~~**2.7 → 2.2** — Profile rename/update, profile load missing mods report~~
7. ~~**2.3 → 2.8 → 2.5** — Inactive sorting, auto-save toggles, positional drag~~
8. ~~**2.4 → 2.6** — PAK Inspector, advanced filters~~
9. ~~**3.5** — Test suite (pays dividends before larger features)~~
10. ~~**3.6 → 3.7 → 3.2** — Per-mod notes, bulk Nexus import, update detection~~
11. **3.3 → 3.1 → 3.4** — Mod groups, history panel, conflict advisor
