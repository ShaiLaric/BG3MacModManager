// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import AppKit
import UniformTypeIdentifiers

@main
struct BG3MacModManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
                    appDelegate.appState = appState
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

            CommandGroup(replacing: .undoRedo) {
                Button("Undo") {
                    appState.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!appState.canUndo)

                Button("Redo") {
                    appState.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!appState.canRedo)
            }

            CommandGroup(after: .toolbar) {
                Button("Deactivate Selected") {
                    appState.deactivateSelectedMods()
                }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(appState.selectedModIDs.isEmpty)

                Button("Launch Baldur's Gate 3") {
                    Task { await appState.launchGame() }
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
        appState.showModImportPicker = true
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

// MARK: - Unsaved Changes on Close/Quit

/// Response from the unsaved changes confirmation alert.
private enum UnsavedChangesResponse {
    case save, dontSave, cancel
}

/// Application delegate that intercepts quit and window close to prompt for
/// unsaved changes, implementing the standard macOS "Save changes?" dialog.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    /// Reference to the shared app state, set by BG3MacModManagerApp on appear.
    var appState: AppState?

    // MARK: - App Termination

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState = appState, appState.hasUnsavedChanges else {
            return .terminateNow
        }

        let response = showUnsavedChangesAlert()
        switch response {
        case .save:
            Task { @MainActor in
                await appState.performSave()
                NSApplication.shared.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        case .dontSave:
            return .terminateNow
        case .cancel:
            return .terminateCancel
        }
    }

    // MARK: - Window Close

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            if let window = NSApplication.shared.windows.first {
                window.delegate = self
            }
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard let appState = appState, appState.hasUnsavedChanges else {
            return true
        }

        let response = showUnsavedChangesAlert()
        switch response {
        case .save:
            Task { @MainActor in
                await appState.performSave()
                sender.close()
            }
            return false
        case .dontSave:
            return true
        case .cancel:
            return false
        }
    }

    // MARK: - Alert

    private func showUnsavedChangesAlert() -> UnsavedChangesResponse {
        let alert = NSAlert()
        alert.messageText = "You have unsaved changes"
        alert.informativeText = "Do you want to save your mod load order before closing?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[1].keyEquivalent = "d"
        alert.buttons[1].keyEquivalentModifierMask = [.command]

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            return .save
        case .alertSecondButtonReturn:
            return .dontSave
        default:
            return .cancel
        }
    }
}
