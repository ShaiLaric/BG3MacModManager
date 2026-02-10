# BG3 Mac Mod Manager

A native macOS application for managing Baldur's Gate 3 mods, inspired by [LaughingLeader's BG3 Mod Manager](https://github.com/LaughingLeader/BG3ModManager) for Windows.

Built with Swift and SwiftUI, this tool provides a first-class macOS experience for installing, organizing, and managing BG3 mods — including full integration with [bg3se-macos](https://github.com/tdimino/bg3se-macos) (Script Extender for macOS).

## Features

### Mod Management
- **Discover & import mods** — scans your Mods folder and imports `.pak` files (or ZIPs containing them)
- **Drag-and-drop load order** — reorder active mods to control load priority
- **Activate / deactivate** — toggle mods between active and inactive with a click
- **Rich metadata** — displays name, author, version, description, UUID, dependencies, and tags parsed from `info.json` or `meta.lsx` inside `.pak` files
- **Dependency warnings** — flags mods with missing dependencies
- **Search & filter** — find mods by name, author, folder, or tags

### PAK File Reading
- **Native LSPK v18 reader** — reads Larian's proprietary `.pak` archive format directly, with no external tools
- **Extracts `meta.lsx`** — parses mod metadata from inside `.pak` files when `info.json` isn't available
- **LZ4 & Zlib decompression** — handles both Solid and non-Solid compressed archives using macOS's built-in Compression framework

### modsettings.lsx Management
- **Reads & writes** the game's `modsettings.lsx` configuration file
- **Preserves GustavDev** — always keeps the required base game module entry
- **Auto-backup** — creates a timestamped backup before every save
- **File locking** — optionally locks `modsettings.lsx` (via `chflags uchg`) to prevent the game from overwriting your configuration

### Profiles
- **Save** your current mod configuration (load order + active mods) as a named profile
- **Load** profiles to quickly switch between setups
- **Import / export** profiles as JSON for sharing with others

### Script Extender Integration
- **Status detection** — checks if `bg3se-macos` is installed and deployed
- **SE mod flagging** — identifies mods that require the Script Extender (by detecting `ScriptExtender/Config.json` inside `.pak` files)
- **Installation guide** — provides step-by-step instructions for installing bg3se-macos
- **Log viewer** — read SE logs directly from the app
- **Debug options** — documents `BG3SE_NO_HOOKS`, `BG3SE_NO_NET`, `BG3SE_MINIMAL` environment variables

### Game Launch
- **Launch BG3** directly from the app via Steam
- **Quick access** — open Mods folder, modsettings.lsx, or SE logs in Finder

## Requirements

- **macOS 13 (Ventura)** or later
- **Baldur's Gate 3** installed via Steam
- **Xcode 15+** or Swift 5.9+ toolchain (for building)
- [bg3se-macos](https://github.com/tdimino/bg3se-macos) (optional, for Script Extender mods)

## Building

```bash
# Clone the repository
git clone https://github.com/ShaiLaric/BG3MacModManager.git
cd BG3MacModManager

# Build with Swift Package Manager
swift build

# Run
swift run BG3MacModManager

# Or open in Xcode
open Package.swift
```

For release builds:
```bash
swift build -c release
```

## File Locations

The app works with these standard BG3 paths on macOS:

| Item | Path |
|------|------|
| Mods folder | `~/Documents/Larian Studios/Baldur's Gate 3/Mods/` |
| Mod settings | `~/Documents/Larian Studios/Baldur's Gate 3/PlayerProfiles/Public/modsettings.lsx` |
| Save games | `~/Documents/Larian Studios/Baldur's Gate 3/PlayerProfiles/Public/Savegames/Story/` |
| Game (Steam) | `~/Library/Application Support/Steam/steamapps/common/Baldurs Gate 3/` |
| SE dylib | `...Baldur's Gate 3.app/Contents/MacOS/libbg3se.dylib` |
| SE logs | `~/Library/Application Support/BG3SE/logs/` |
| App profiles | `~/Library/Application Support/BG3MacModManager/Profiles/` |
| App backups | `~/Library/Application Support/BG3MacModManager/Backups/` |

## Project Structure

```
Sources/BG3MacModManager/
├── App/
│   ├── BG3MacModManagerApp.swift   # SwiftUI app entry point
│   └── AppState.swift              # Central observable state
├── Models/
│   ├── ModInfo.swift               # Mod data model
│   └── ModProfile.swift            # Profile data model
├── Services/
│   ├── PakReader.swift             # LSPK v18 .pak file reader
│   ├── ModSettingsService.swift    # modsettings.lsx read/write
│   ├── ModDiscoveryService.swift   # Mod folder scanning
│   ├── ScriptExtenderService.swift # bg3se-macos integration
│   ├── ProfileService.swift        # Profile save/load
│   ├── BackupService.swift         # Backup management
│   └── GameLaunchService.swift     # Game launch via Steam
├── Views/
│   ├── ContentView.swift           # Main window with sidebar
│   ├── ModListView.swift           # Active/inactive mod lists
│   ├── ModRowView.swift            # Single mod row
│   ├── ModDetailView.swift         # Mod detail panel
│   ├── ProfileManagerView.swift    # Profile management
│   ├── BackupManagerView.swift     # Backup management
│   ├── SEStatusView.swift          # Script Extender status
│   └── SettingsView.swift          # App preferences
└── Utilities/
    ├── FileLocations.swift         # macOS file path registry
    └── Version64.swift             # BG3 version encoding/decoding
```

## How It Works

### Mod Discovery
1. Scans `~/Documents/Larian Studios/Baldur's Gate 3/Mods/` for `.pak` files
2. For each `.pak`, attempts to read metadata in this order:
   - `info.json` alongside the `.pak` file (most common for NexusMods downloads)
   - `meta.lsx` extracted from inside the `.pak` file (requires LSPK v18 parsing)
   - Falls back to deriving the mod name from the filename
3. Cross-references with `modsettings.lsx` to determine active/inactive state

### Load Order
- The `ModOrder` section of `modsettings.lsx` defines which mods load and in what order
- **Last loaded wins** for conflicting changes — mods later in the list override earlier ones
- `GustavDev` (the base game module) is always preserved as the first entry

### macOS-Specific Notes
- Only `.pak`-based mods work on macOS (no DLL/native mods)
- The Mods directory must be flat — no subdirectories (the game resets `modsettings.lsx` otherwise)
- File locking via `chflags uchg` prevents the game from overwriting your settings

## Contributing

Contributions are welcome! Please feel free to open issues or submit pull requests.

## License

This project is open source. See the LICENSE file for details.

## Acknowledgments

- [LaughingLeader/BG3ModManager](https://github.com/LaughingLeader/BG3ModManager) — the original Windows BG3 Mod Manager
- [tdimino/bg3se-macos](https://github.com/tdimino/bg3se-macos) — Script Extender for macOS
- [Norbyte/lslib](https://github.com/Norbyte/lslib) — reference for LSPK format and LSX parsing
- [BG3 Modding Wiki](https://bg3.wiki/wiki/Modding:Installing_mods) — modding documentation
