import SwiftUI

@main
struct BG3MacModManagerApp: App {
    @StateObject private var appState = AppState()

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

                Divider()

                Button("Refresh Mods") {
                    Task { await appState.refreshMods() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
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
            .init(filenameExtension: "zip")!
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        if panel.runModal() == .OK {
            for url in panel.urls {
                Task {
                    await appState.importMod(from: url)
                }
            }
        }
    }
}
