# CLAUDE.md

## Project Overview

BG3 Mac Mod Manager is a macOS SwiftUI application for managing Baldur's Gate 3 mods. It uses Swift Package Manager (SPM) with swift-tools-version 5.9, targeting macOS 13+.

## Build Environment

**Do not attempt `swift build`, `swift test`, or any Swift toolchain commands.** The CI/CD environment does not have Swift installed. Verify correctness by reading code and checking that changes follow existing patterns.

## Project Structure

```
Sources/BG3MacModManager/
  App/          - App entry point (BG3MacModManagerApp), AppState
  Models/       - Data models (ModModel, ModCategory, etc.)
  Services/     - Business logic (ModService, LaunchService, etc.)
  Utilities/    - Helpers (FileLocations, etc.)
  Views/        - SwiftUI views (ContentView, ModListView, etc.)
Tests/BG3MacModManagerTests/
```

## Key Patterns

- **Icons**: SF Symbols only — no custom image assets
- **Button styles**: `.borderedProminent` for primary actions, `.bordered` for secondary, `.plain` for icon-only
- **Toolbar**: Standard macOS toolbar in ContentView; in-content action bars in views like ModListView for prominent buttons
- **All buttons** should have `.help()` tooltips
- **State**: Single `AppState` (ObservableObject) passed via `.environmentObject()`
- **Async**: Use `Task { await ... }` in button actions for async AppState methods

## Dependencies

- [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) (>=0.9.19) — ZIP archive handling
