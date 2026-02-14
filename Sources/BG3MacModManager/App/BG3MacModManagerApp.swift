import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct BG3MacModManagerApp: App {
    @StateObject private var appState = AppState()

    init() {
        // SPM executables launch as background processes by default.
        // This makes the app appear in the Dock and show its window.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .onAppear {
                    appState.initialLoad()
                }
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1100, height: 750)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Import Mod...") {
                    importModFromPanel()
                }
                .keyboardShortcut("i", modifiers: .command)

                Button("Import from Save File...") {
                    importFromSavePanel()
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])

                Button("Import Load Order...") {
                    importLoadOrderPanel()
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Divider()

                Button("Refresh Mods") {
                    Task { await appState.refreshMods() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save Load Order") {
                    Task { await appState.saveModSettings() }
                }
                .keyboardShortcut("s", modifiers: .command)

                Divider()

                Button("Export Load Order as ZIP...") {
                    appState.exportLoadOrderToZip()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(appState.activeMods.isEmpty || appState.isExporting)
            }

            CommandGroup(after: .toolbar) {
                Button("Deactivate Selected") {
                    appState.deactivateSelectedMods()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(appState.selectedModIDs.isEmpty)

                Button("Launch Baldur's Gate 3") {
                    appState.launchGame()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!appState.isGameInstalled)
            }

            CommandGroup(replacing: .help) {
                Button("BG3 Mac Mod Manager Help") {
                    appState.navigateToSidebarItem = "help"
                }
                .keyboardShortcut("?", modifiers: .command)
                Divider()
                Button("Open Mods Folder") {
                    appState.launchService.openModsFolder()
                }
                Button("Open modsettings.lsx") {
                    appState.launchService.openModSettings()
                }
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
        #endif
    }

    private func importModFromPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Mod"
        panel.allowedContentTypes = [
            .init(filenameExtension: "pak")!,
            .init(filenameExtension: "zip")!,
            .init(filenameExtension: "tar")!,
            .init(filenameExtension: "gz")!,
            .init(filenameExtension: "tgz")!,
            .init(filenameExtension: "bz2")!,
            .init(filenameExtension: "xz")!,
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, !panel.urls.isEmpty {
            Task {
                await appState.importMods(from: panel.urls)
            }
        }
    }

    private func importFromSavePanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Load Order from Save File"
        panel.message = "Select a BG3 save file (.lsv) to import its mod load order"
        panel.allowedContentTypes = [
            .init(filenameExtension: "lsv")!,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        // Default to the saves directory if it exists
        let savesDir = FileLocations.savegamesFolder
        if FileManager.default.fileExists(atPath: savesDir.path) {
            panel.directoryURL = savesDir
        }

        if panel.runModal() == .OK, let url = panel.urls.first {
            Task {
                await appState.importFromSaveFile(url: url)
            }
        }
    }

    private func importLoadOrderPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Load Order"
        panel.message = "Select a BG3 Mod Manager JSON export or modsettings.lsx file"
        panel.allowedContentTypes = [
            .init(filenameExtension: "json")!,
            .init(filenameExtension: "lsx")!,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.urls.first {
            Task {
                await appState.importLoadOrder(from: url)
            }
        }
    }
}
