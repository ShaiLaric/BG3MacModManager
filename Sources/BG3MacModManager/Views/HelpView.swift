// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// In-app help documentation covering all features of BG3 Mac Mod Manager.
struct HelpView: View {
    @State private var selectedSection: HelpSection = .gettingStarted

    enum HelpSection: String, CaseIterable, Identifiable {
        case gettingStarted = "Getting Started"
        case modManagement = "Mod Management"
        case loadOrder = "Load Order & Sorting"
        case deletingMods = "Deleting Mods"
        case profiles = "Profiles"
        case importExport = "Import & Export"
        case backups = "Backups"
        case scriptExtender = "Script Extender"
        case validation = "Validation & Warnings"
        case tools = "Tools"
        case settings = "Settings"
        case keyboardShortcuts = "Keyboard Shortcuts"
        case troubleshooting = "Troubleshooting"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .gettingStarted: return "play.circle"
            case .modManagement: return "puzzlepiece.extension"
            case .loadOrder: return "list.number"
            case .deletingMods: return "trash"
            case .profiles: return "person.2"
            case .importExport: return "square.and.arrow.up.on.square"
            case .backups: return "clock.arrow.circlepath"
            case .scriptExtender: return "terminal"
            case .validation: return "exclamationmark.triangle"
            case .tools: return "wrench.and.screwdriver"
            case .settings: return "gear"
            case .keyboardShortcuts: return "keyboard"
            case .troubleshooting: return "ladybug"
            }
        }
    }

    var body: some View {
        HSplitView {
            // Left: Section navigation
            List(HelpSection.allCases, selection: $selectedSection) { section in
                Label(section.rawValue, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 200, idealWidth: 220)

            // Right: Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sectionContent(for: selectedSection)
                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Section Router

    @ViewBuilder
    private func sectionContent(for section: HelpSection) -> some View {
        switch section {
        case .gettingStarted:
            gettingStartedContent
        case .modManagement:
            modManagementContent
        case .loadOrder:
            loadOrderContent
        case .deletingMods:
            deletingModsContent
        case .profiles:
            profilesContent
        case .importExport:
            importExportContent
        case .backups:
            backupsContent
        case .scriptExtender:
            scriptExtenderContent
        case .validation:
            validationContent
        case .tools:
            toolsContent
        case .settings:
            settingsContent
        case .keyboardShortcuts:
            keyboardShortcutsContent
        case .troubleshooting:
            troubleshootingContent
        }
    }

    // MARK: - Getting Started

    private var gettingStartedContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpTitle("Getting Started")

            helpText("""
            BG3 Mac Mod Manager is a native macOS application for managing Baldur's Gate 3 mods. \
            It reads and writes the game's modsettings.lsx file to control which mods are active \
            and in what order they load.
            """)

            helpHeading("First Launch")
            helpText("""
            On first launch, the app automatically scans your Mods folder and reads your current \
            modsettings.lsx to determine which mods are active and inactive. The app looks for mods at:
            """)
            helpCode("~/Documents/Larian Studios/Baldur's Gate 3/Mods/")

            helpText("The mod settings file is located at:")
            helpCode("~/Documents/Larian Studios/Baldur's Gate 3/PlayerProfiles/Public/modsettings.lsx")

            helpHeading("Basic Workflow")
            helpNumberedList([
                "Install mods by placing .pak files in the Mods folder, or by importing them via File > Import Mod (Cmd+I) or drag-and-drop.",
                "Activate mods by right-clicking an inactive mod and choosing \"Activate\", or by dragging mods from the Inactive list to the Active list.",
                "Arrange load order by dragging mods up or down in the Active list, or use Smart Sort to auto-arrange by community convention.",
                "Save your configuration by clicking Save Load Order in the action bar (this writes modsettings.lsx).",
                "Launch the game from the action bar or directly from Steam.",
            ])

            helpHeading("Sidebar Navigation")
            helpText("""
            Use the sidebar on the left to navigate between sections:
            """)
            helpBulletList([
                "Mods — Main view for managing active and inactive mods",
                "Profiles — Save and load named mod configurations",
                "Backups — View and restore modsettings.lsx backups",
                "Script Extender — Check bg3se-macos installation status",
                "Tools — Version number converter and PAK file inspector",
                "Help — This documentation",
            ])
        }
    }

    // MARK: - Mod Management

    private var modManagementContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpTitle("Mod Management")

            helpText("""
            The Mods view is the main screen of the app. It is split into three areas: \
            the Active Mods list (top-left), the Inactive Mods list (bottom-left), and \
            the Detail Panel (right).
            """)

            helpHeading("Active Mods")
            helpText("""
            Active mods are in your current load order and will be written to modsettings.lsx \
            when you save. The order matters — mods are loaded from top to bottom. The base game \
            module (GustavX) is always present and cannot be deactivated.
            """)

            helpHeading("Inactive Mods")
            helpText("""
            Inactive mods are .pak files discovered in your Mods folder that are not in your \
            current load order. They are not written to modsettings.lsx and will not load in-game.
            """)

            helpHeading("Inactive Mods Sorting")
            helpText("""
            The inactive mod list can be sorted using the sort picker in the section header. \
            Available sort options:
            """)
            helpBulletList([
                "Name — Alphabetical by mod name (default)",
                "Author — Alphabetical by author name",
                "Category — By load order tier (Framework, Gameplay, Content, Visual, Late Loader)",
                "File Date — By PAK file modification date",
                "File Size — By PAK file size on disk",
            ])
            helpText("""
            Click the arrow button next to the sort picker to toggle between ascending and \
            descending order. Your sort preference is remembered across sessions.
            """)

            helpHeading("Activating & Deactivating")
            helpBulletList([
                "Double-click a mod row to toggle it between active and inactive",
                "Right-click a mod and choose Activate or Deactivate",
                "Click the +/- button on the right side of a mod row",
                "Drag an inactive mod onto the Active Mods list to activate it at a specific position in the load order",
                "Use the overflow menu (\"...\") to Activate All or Deactivate All",
                "Multi-select mods (Cmd+Click or Shift+Click) and use the action bar for bulk operations",
            ])

            helpHeading("Mod Row Information")
            helpText("""
            Each mod row shows the mod name, category badge, author, version, and a single-line \
            description preview (if the mod has a description). Active mods also show their load \
            order position number on the left.
            """)

            helpHeading("Detail Panel")
            helpText("""
            Click on any mod to see its full details in the right panel, including:
            """)
            helpBulletList([
                "Name, author, and version",
                "Load order category (for Smart Sort)",
                "Nexus Mods URL (manually set per mod)",
                "Validation warnings specific to this mod",
                "UUID, folder name, and metadata source",
                "Dependencies with status indicators (satisfied or missing)",
                "Full transitive dependency tree",
                "Declared conflicts with active-status warnings",
                "Tags from mod metadata",
                "File path with Reveal in Finder",
            ])

            helpHeading("Context Menu Actions")
            helpText("""
            Right-click any mod to access a context menu with actions specific to that mod. \
            The available actions depend on whether the mod is active or inactive:
            """)
            helpBulletList([
                "Move to Top / Move to Bottom — Quickly reorder an active mod to the start or end of the load order (after the base game module).",
                "Open on Nexus Mods — Opens the mod's Nexus Mods page if a URL has been set, or searches Nexus Mods for the mod by name.",
                "Copy Mod Info — Copies a formatted summary of the mod (name, author, version, UUID, category, and Nexus URL) to the clipboard. Useful for sharing your mod list or reporting issues.",
                "Copy UUID — Copies just the mod's UUID to the clipboard.",
                "Reveal in Finder — Shows the mod's PAK file in Finder.",
                "Extract to Folder... — Extracts the mod's PAK archive contents to a folder of your choice.",
                "Delete from Disk... — Permanently removes an inactive mod's PAK file (see Deleting Mods section).",
            ])

            helpHeading("Multi-Selection")
            helpText("""
            Hold Cmd and click to select multiple mods, or Shift+Click to select a range. \
            When multiple mods are selected, an action bar appears with bulk Activate, Deactivate, \
            and Clear options. Right-click context menus also offer bulk operations on the selection.
            """)

            helpHeading("Searching / Filtering")
            helpText("""
            Use the search field at the top to filter mods by name, author, folder, or tags. \
            The filter applies to both active and inactive mod lists simultaneously.
            """)

            helpHeading("Category Filter Chips")
            helpText("""
            A row of category filter chips appears above the mod lists (shown automatically when \
            you have more than 20 mods). Click a category chip to toggle filtering by that category. \
            Multiple categories can be selected simultaneously. The "Uncategorized" chip controls \
            whether mods without a category assignment are shown. Click "Clear" to reset all filters.
            """)
            helpText("""
            Note: Drag-and-drop reordering is disabled while category or advanced filters are active, \
            since the filtered view does not show all mods.
            """)

            helpHeading("Advanced Filters")
            helpText("""
            Click the filter icon at the end of the category filter bar to open the advanced filter \
            popover. Advanced filters let you narrow the mod list by:
            """)
            helpBulletList([
                "Script Extender — Show only mods that require SE, only mods that don't, or all",
                "Warnings — Show only mods with validation warnings, only mods without warnings, or all",
                "Metadata Source — Show only mods discovered via a specific method (meta.lsx, info.json, filename, or modsettings.lsx)",
            ])
            helpText("""
            Active advanced filters are indicated by a filled filter icon and a badge showing the \
            count of active filters. Use \"Clear All\" in the popover or the \"Clear\" button in \
            the filter bar to reset all filters.
            """)
        }
    }

    // MARK: - Load Order & Sorting

    private var loadOrderContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpTitle("Load Order & Sorting")

            helpText("""
            Load order determines which mods take priority. Mods loaded later can override files \
            from mods loaded earlier. Getting load order right is important — incorrect ordering \
            can cause crashes or missing content.
            """)

            helpHeading("Manual Ordering")
            helpText("""
            Drag mods up or down in the Active Mods list to reorder them. The number shown on the \
            left of each row indicates its position in the load order. You can also right-click a mod \
            and choose \"Move to Top\" or \"Move to Bottom\" for quick repositioning.
            """)

            helpHeading("Smart Sort")
            helpText("""
            Click the Smart Sort button to automatically arrange mods using the BG3 community's \
            5-tier load order convention. Mods are grouped into tiers, then sorted by dependencies \
            within each tier:
            """)
            helpNumberedList([
                "Framework — Libraries and APIs (e.g., Mod Fixer, Compatibility Framework)",
                "Gameplay — Mechanics changes, bug fixes, balance adjustments",
                "Content Extension — New classes, spells, feats, subclasses",
                "Visual — Cosmetics, textures, UI changes",
                "Late Loader — Compatibility patches and overrides that must load last",
            ])

            helpText("""
            The app auto-detects categories from mod tags and names. You can manually override \
            a mod's category in the Detail Panel using the category picker. Choose \"Auto-detect\" \
            to clear a manual override.
            """)

            helpHeading("Dependency Sort")
            helpText("""
            Use the overflow menu and choose \"Sort by Dependencies Only\" for a pure topological \
            sort based on declared mod dependencies, without considering category tiers.
            """)

            helpHeading("Activate Missing Dependencies")
            helpText("""
            From the overflow menu, choose \"Activate Missing Dependencies\" to find all dependencies \
            required by your active mods that are sitting in the inactive list, and activate them \
            automatically. Dependencies are inserted before the mods that need them.
            """)

            helpHeading("Undo & Redo")
            helpText("""
            Every load order change (activating, deactivating, moving, sorting, importing, etc.) \
            can be undone with Cmd+Z and redone with Cmd+Shift+Z. The undo history stores up to \
            50 snapshots. Undo/Redo is also available from the Edit menu.
            """)

            helpHeading("Unsaved Changes Protection")
            helpText("""
            If you close the window or quit the app while you have unsaved changes to your load \
            order, a confirmation dialog appears asking whether to Save, Don't Save, or Cancel. \
            This prevents accidentally losing your load order changes.
            """)
        }
    }

    // MARK: - Deleting Mods

    private var deletingModsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpTitle("Deleting Mods")

            helpWarning("""
            Deleting a mod permanently removes its .pak file from your Mods folder. This action \
            cannot be undone. Make sure you have a backup or can re-download the mod before deleting.
            """)

            helpHeading("How to Delete a Mod")
            helpText("""
            Mods can only be deleted when they are in the Inactive list. This prevents \
            accidentally removing a mod that is part of your active load order. To delete \
            an active mod, first deactivate it.
            """)

            helpText("There are three ways to delete an inactive mod:")

            helpNumberedList([
                "Right-click an inactive mod and choose \"Delete from Disk...\" from the context menu.",
                "Select an inactive mod and click the \"Delete from Disk...\" button in the File Info section of the Detail Panel.",
                "Multi-select several inactive mods (Cmd+Click), then right-click and choose \"Delete N Selected from Disk...\".",
            ])

            helpHeading("Confirmation Dialog")
            helpText("""
            Every deletion shows a confirmation dialog listing the mod(s) to be deleted. \
            You must explicitly click \"Delete Permanently\" to proceed. The dialog warns \
            that the action cannot be undone.
            """)

            helpHeading("What Gets Deleted")
            helpBulletList([
                "The mod's .pak file is removed from the Mods folder",
                "The companion info.json file (if present) is also removed",
                "The mod disappears from both the active and inactive lists after refresh",
            ])

            helpHeading("Duplicate Resolution")
            helpText("""
            When multiple .pak files share the same mod UUID, the app shows a Duplicate Resolver \
            dialog. This lets you choose which copy to keep and delete the others. The Duplicate \
            Resolver is accessible from validation warnings when duplicates are detected.
            """)
        }
    }

    // MARK: - Profiles

    private var profilesContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpTitle("Profiles")

            helpText("""
            Profiles let you save and restore named mod configurations. Each profile stores \
            the list of active mod UUIDs and their order, so you can quickly switch between \
            different mod setups (e.g., a \"vanilla+\" setup and a \"full overhaul\" setup).
            """)

            helpHeading("Saving a Profile")
            helpText("""
            Click \"Save Current...\" in the Profiles view to save your current active mod \
            configuration. Give the profile a descriptive name. The profile stores full mod \
            metadata for portability.
            """)

            helpHeading("Loading a Profile")
            helpText("""
            Click \"Load\" next to a saved profile to restore that configuration. Mods that \
            are in the profile but not found in your Mods folder will appear as placeholders. \
            Loading a profile does not automatically save to modsettings.lsx — you still need \
            to click Save.
            """)

            helpHeading("Import & Export Profiles")
            helpBulletList([
                "Export a profile as a JSON file to share with others or back up",
                "Import a profile from a JSON file",
                "Profiles are stored in ~/Library/Application Support/BG3MacModManager/Profiles/",
            ])

            helpHeading("Exporting Load Order as Text")
            helpText("""
            From the Profiles view, use the \"Export List\" menu to export your current load \
            order as CSV, Markdown, or Plain Text. This is useful for sharing your mod list \
            in forums or documentation.
            """)

            helpHeading("Exporting as ZIP")
            helpText("""
            Click \"Export ZIP\" to create a ZIP archive containing all active mod PAK files, \
            a profile JSON snapshot, and your modsettings.lsx. This is a complete backup of \
            your entire modded setup that can be shared or archived.
            """)
        }
    }

    // MARK: - Import & Export

    private var importExportContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpTitle("Import & Export")

            helpHeading("Importing Mods")
            helpText("There are several ways to import mod files:")
            helpBulletList([
                "File > Import Mod (Cmd+I) — Opens a file picker for .pak, .zip, .tar, and other archive formats",
                "Drag and drop — Drag mod files directly onto the app window from Finder",
                "Manual — Place .pak files directly in the Mods folder and click Refresh",
            ])
            helpText("""
            When importing archives (.zip, .tar, etc.), the app extracts all .pak files and \
            their companion info.json files into the Mods folder. After import, you are prompted \
            to activate the newly imported mods.
            """)

            helpHeading("Importing Load Orders")
            helpText("You can import a load order from external sources:")
            helpBulletList([
                "File > Import from Save File (Cmd+Shift+I) — Extract the load order from a BG3 save file (.lsv)",
                "File > Import Load Order (Cmd+Shift+L) — Import from a BG3 Mod Manager JSON export or a standalone modsettings.lsx file",
            ])
            helpText("""
            When importing a load order, mods that are referenced but not found in your Mods \
            folder are shown in a summary dialog with links to Nexus Mods (if URLs have been set).
            """)

            helpHeading("Exporting")
            helpBulletList([
                "Export List — Export load order as CSV, Markdown, or Plain Text (from Profiles view)",
                "Export ZIP — Bundle all active mod PAKs, profile data, and modsettings.lsx into a ZIP archive (from Profiles view)",
                "Export Profile — Save a profile as a portable JSON file",
            ])
        }
    }

    // MARK: - Backups

    private var backupsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpTitle("Backups")

            helpText("""
            The app automatically creates backups of your modsettings.lsx file before every save. \
            Backups are stored in:
            """)
            helpCode("~/Library/Application Support/BG3MacModManager/Backups/")

            helpHeading("Automatic Backups")
            helpText("""
            Each time you save your mod configuration, the existing modsettings.lsx is backed up \
            with a timestamp. This means you can always recover a previous load order if something \
            goes wrong.
            """)

            helpHeading("Manual Backups")
            helpText("""
            Click \"Create Backup\" in the Backups view to make a manual backup at any time.
            """)

            helpHeading("Restoring a Backup")
            helpText("""
            Click \"Restore\" next to any backup to replace your current modsettings.lsx with \
            that backup. A safety backup of the current state is created first. You will be asked \
            to confirm before restoring.
            """)

            helpHeading("External Change Detection")
            helpText("""
            The app tracks a hash of modsettings.lsx after each save. If the file is modified \
            externally (e.g., by the game resetting it), you are prompted on next launch to \
            restore from your most recent backup.
            """)

            helpHeading("File Locking")
            helpText("""
            After saving, the app locks modsettings.lsx using the system immutable flag to \
            prevent the game from overwriting your configuration. The lock is automatically \
            removed before the next save.
            """)

            helpHeading("Backup Retention")
            helpText("""
            By default, backups are kept for 30 days. You can change the retention period \
            in Settings > General > Backups, or choose to keep backups forever.
            """)
        }
    }

    // MARK: - Script Extender

    private var scriptExtenderContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpTitle("Script Extender (bg3se-macos)")

            helpText("""
            Some BG3 mods require the Script Extender (bg3se-macos) to function. The Script \
            Extender tab shows whether SE is installed and deployed in your game bundle.
            """)

            helpHeading("Status Detection")
            helpText("""
            The app checks for the presence of libbg3se.dylib in the game's MacOS directory. \
            A green indicator in the status bar shows \"SE Active\" when detected, and a gray \
            indicator shows \"SE Not Found\" otherwise.
            """)

            helpHeading("SE-Dependent Mods")
            helpText("""
            Mods that require Script Extender are tagged with an orange \"Script Extender\" \
            badge in the mod list. The Script Extender tab lists all SE-dependent mods and \
            shows whether they are currently active or inactive.
            """)

            helpHeading("Warnings")
            helpText("""
            If you have active mods that require Script Extender but SE is not detected, the \
            app shows a validation warning. If SE was previously deployed but is no longer found \
            (e.g., after a game update), you receive an additional warning.
            """)

            helpHeading("Installation")
            helpText("""
            If Script Extender is not installed, the app shows installation instructions. \
            bg3se-macos must be built from source and deployed manually. See the bg3se-macos \
            GitHub repository for full instructions.
            """)

            helpHeading("Logs")
            helpText("""
            When SE is installed, the app provides access to SE logs for debugging. You can \
            view the latest log inline or open the logs folder in Finder.
            """)
        }
    }

    // MARK: - Validation & Warnings

    private var validationContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpTitle("Validation & Warnings")

            helpText("""
            The app continuously validates your mod configuration and displays warnings in a \
            collapsible banner at the top of the Mods view. Warnings are also shown per-mod \
            in the Detail Panel.
            """)

            helpHeading("Warning Severities")
            helpBulletList([
                "Critical (red) — Issues that are likely to cause crashes or the game resetting your load order. Critical warnings trigger a confirmation dialog when saving.",
                "Warning (yellow) — Issues that may cause problems but are not guaranteed to break things.",
                "Info (blue) — Informational notices about your configuration.",
            ])

            helpHeading("Types of Warnings")
            helpBulletList([
                "Duplicate UUIDs — Two or more .pak files share the same mod UUID. Use the Duplicate Resolver to keep only one copy.",
                "Missing Dependencies — An active mod requires another mod that is not in the active list. Click \"Activate Deps\" to resolve.",
                "Dependency Order — A dependency is loaded after the mod that needs it. Click \"Auto-Sort\" to fix ordering.",
                "Conflicting Mods — Two active mods declare a conflict with each other. Consider deactivating one.",
                "Script Extender Missing — Active mods require SE but it is not detected.",
                "Script Extender Removed — SE was previously deployed but is no longer found (possibly after a game update).",
                "ModCrashSanityCheck — The game created a folder that causes mod deactivation. Click \"Delete Folder\" to remove it.",
            ])

            helpHeading("Save Confirmation")
            helpText("""
            When saving with critical warnings, the app shows a confirmation dialog listing \
            the issues. You can choose to save anyway or cancel and fix the issues first.
            """)
        }
    }

    // MARK: - Tools

    private var toolsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpTitle("Tools")

            helpText("""
            The Tools section contains utility tools accessible via a segmented picker at the top. \
            Switch between tools by clicking the tabs.
            """)

            helpHeading("Version Generator")
            helpText("""
            BG3 uses a special Int64 format for version numbers (e.g., 36028797018963968 = 1.0.0.0). \
            The Version Generator converts between human-readable version strings (major.minor.revision.build) \
            and the raw Int64 values used in meta.lsx and info.json files.
            """)
            helpText("""
            This is useful for mod authors who need to set version numbers in their mod metadata.
            """)

            helpHeading("PAK Inspector")
            helpText("""
            The PAK Inspector lets you open any .pak (LSPK v18) archive and examine its contents \
            without extracting the entire file. Use it to:
            """)
            helpBulletList([
                "View archive header information (version, flags, priority, solid compression status)",
                "Browse the complete file listing with sizes and compression details",
                "Quickly view meta.lsx and info.json metadata files",
                "Extract and view individual files from within the archive",
                "Search/filter the file list by name",
                "Copy file paths from within the archive",
            ])
            helpText("""
            Right-click any file in the list to view its contents or copy its path. This is useful \
            for debugging mod issues, verifying mod contents, or inspecting unfamiliar PAK files.
            """)

            helpHeading("Extract to Folder")
            helpText("""
            Right-click any mod (active or inactive) and choose \"Extract to Folder...\" to \
            extract all files from the mod's .pak archive to a folder of your choice. This is \
            useful for inspecting mod contents or extracting assets.
            """)

            helpHeading("Reveal in Finder")
            helpText("""
            Right-click any mod and choose \"Reveal in Finder\" from the context menu to show \
            the mod's .pak file in Finder. This is also available in the Detail Panel's File Info \
            section via the arrow button next to the file path.
            """)

            helpHeading("Copy Mod Info")
            helpText("""
            Right-click any mod and choose \"Copy Mod Info\" to copy a formatted summary including \
            name, author, version, UUID, category, and Nexus URL to the clipboard. This is useful \
            for sharing your mod setup or filing bug reports.
            """)

            helpHeading("Copy UUID / Folder")
            helpText("""
            In the Detail Panel, click the copy button next to the UUID or Folder fields to \
            copy the value to your clipboard. UUIDs are also available via the right-click context menu.
            """)
        }
    }

    // MARK: - Settings

    private var settingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpTitle("Settings")

            helpText("""
            Open Settings from the app menu (Cmd+,) to configure app behavior.
            """)

            helpHeading("General")
            helpBulletList([
                "Lock modsettings.lsx after saving — When enabled, the file is made immutable to prevent the game from overwriting it. Enabled by default.",
                "Auto-backup before saving — Creates a backup before every save. Enabled by default.",
                "Auto-save before launching game — Automatically saves your load order before launching BG3. Disabled by default.",
                "Auto-save when loading a profile — Automatically saves your load order after loading a profile. Disabled by default.",
                "Backup retention — How long to keep automatic backups (7, 14, 30, or 90 days, or forever).",
                "Clean Old Backups — Manually delete backups older than the retention period.",
            ])

            helpHeading("Paths")
            helpText("""
            The Paths tab shows all detected file paths with green/red indicators showing \
            whether each path exists. This is useful for diagnosing issues with game detection \
            or missing files.
            """)

            helpHeading("Script Extender")
            helpText("""
            Shows Script Extender installation and deployment status, along with available \
            debug environment variables for the bg3w.sh launch script.
            """)
        }
    }

    // MARK: - Keyboard Shortcuts

    private var keyboardShortcutsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpTitle("Keyboard Shortcuts")

            helpShortcutTable([
                ("Cmd+Z", "Undo Last Change"),
                ("Cmd+Shift+Z", "Redo Last Change"),
                ("Cmd+S", "Save Load Order"),
                ("Cmd+I", "Import Mod"),
                ("Cmd+Shift+I", "Import from Save File"),
                ("Cmd+Shift+L", "Import Load Order"),
                ("Cmd+Shift+E", "Export Load Order as ZIP"),
                ("Cmd+R", "Refresh Mods"),
                ("Cmd+Delete", "Deactivate Selected Mods"),
                ("Cmd+Shift+G", "Launch Baldur's Gate 3"),
                ("Cmd+Q", "Quit (prompts to save if unsaved)"),
                ("Cmd+,", "Open Settings"),
                ("Cmd+?", "Open Help"),
                ("Cmd+Click", "Add/remove from multi-selection"),
                ("Shift+Click", "Extend selection range"),
                ("Double-Click", "Toggle mod active/inactive"),
            ])
        }
    }

    // MARK: - Troubleshooting

    private var troubleshootingContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            helpTitle("Troubleshooting")

            helpHeading("Game Resets My Mods on Launch")
            helpText("""
            Since Patch 8, BG3 can create a ModCrashSanityCheck folder that causes it to \
            deactivate externally-managed mods. The app automatically deletes this folder on \
            launch. If you see a warning about it, click \"Delete Folder\" to remove it manually.
            """)
            helpText("""
            Also ensure that modsettings.lsx locking is enabled in Settings. This prevents \
            the game from overwriting your configuration.
            """)

            helpHeading("Mods Not Showing Up")
            helpBulletList([
                "Ensure .pak files are placed directly in the Mods folder (not in subfolders)",
                "Click Rescan Folder in the action bar to rescan the Mods folder",
                "Check that the Mods folder path is correct in Settings > Paths",
                "Some mods consist of multiple .pak files — all of them must be present",
            ])

            helpHeading("Game Crashes on Load")
            helpBulletList([
                "Check for conflicting mods (shown as yellow warnings)",
                "Ensure all dependencies are satisfied (shown as red warnings)",
                "Try using Smart Sort to fix load order issues",
                "Restore a working backup from the Backups view",
                "Try deactivating recently added mods to isolate the problem",
            ])

            helpHeading("Script Extender Not Working")
            helpBulletList([
                "Verify SE status in the Script Extender tab",
                "Game updates can remove the deployed dylib — check after each update",
                "Ensure the Steam launch option is set correctly for bg3w.sh",
                "Check SE logs for error messages",
            ])

            helpHeading("External modsettings.lsx Change Detected")
            helpText("""
            This alert appears when something modified modsettings.lsx outside the app. \
            Choose \"Restore from Backup\" to recover your last saved configuration, or \
            \"Keep Current\" to accept the external changes.
            """)

            helpHeading("Duplicate Mods")
            helpText("""
            If you have multiple .pak files with the same mod UUID, the app detects this and \
            shows a Duplicate Resolver dialog. Keep the version you want and delete the others. \
            Having duplicates can cause the game to reset your load order.
            """)
        }
    }

    // MARK: - Reusable Help Components

    private func helpTitle(_ text: String) -> some View {
        Text(text)
            .font(.title.bold())
            .padding(.bottom, 4)
    }

    private func helpHeading(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
            .padding(.top, 8)
    }

    private func helpText(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func helpCode(_ text: String) -> some View {
        Text(text)
            .font(.body.monospaced())
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            .textSelection(.enabled)
    }

    private func helpWarning(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title3)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }

    private func helpBulletList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\u{2022}")
                        .font(.body)
                    Text(item)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func helpNumberedList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1).")
                        .font(.body.monospacedDigit())
                        .frame(width: 20, alignment: .trailing)
                    Text(item)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func helpShortcutTable(_ shortcuts: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(shortcuts, id: \.0) { shortcut, description in
                HStack(spacing: 16) {
                    Text(shortcut)
                        .font(.body.monospaced())
                        .frame(width: 160, alignment: .trailing)
                    Text(description)
                        .font(.body)
                    Spacer()
                }
                .padding(.vertical, 4)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
    }
}
