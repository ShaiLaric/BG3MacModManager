import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSidebarItem: SidebarItem = .mods

    enum SidebarItem: String, CaseIterable, Identifiable {
        case mods = "Mods"
        case profiles = "Profiles"
        case backups = "Backups"
        case scriptExtender = "Script Extender"
        case tools = "Tools"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .mods: return "puzzlepiece.extension"
            case .profiles: return "person.2"
            case .backups: return "clock.arrow.circlepath"
            case .scriptExtender: return "terminal"
            case .tools: return "wrench.and.screwdriver"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
        }
        .toolbar {
            toolbarContent
        }
        .alert("Error", isPresented: $appState.showError, presenting: appState.errorMessage) { _ in
            Button("OK") { appState.showError = false }
        } message: { message in
            Text(message)
        }
        .confirmationDialog(
            "Save with Issues?",
            isPresented: $appState.showSaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Save Anyway", role: .destructive) {
                Task { await appState.performSave() }
            }
            Button("Cancel", role: .cancel) {
                appState.showSaveConfirmation = false
                appState.pendingSaveWarnings = []
            }
        } message: {
            let criticalCount = appState.pendingSaveWarnings.filter { $0.severity == .critical }.count
            let warningCount = appState.pendingSaveWarnings.filter { $0.severity == .warning }.count
            Text("Your mod configuration has \(criticalCount) critical issue(s) and \(warningCount) warning(s) that may cause the game to crash. Save anyway?")
        }
        .sheet(isPresented: $appState.showDuplicateResolver) {
            DuplicateResolverView()
                .environmentObject(appState)
        }
        .alert(
            "External modsettings.lsx Change Detected",
            isPresented: $appState.showExternalChangeAlert
        ) {
            Button("Restore from Backup") {
                Task { await appState.restoreFromLatestBackup() }
            }
            Button("Keep Current", role: .cancel) {
                appState.showExternalChangeAlert = false
            }
        } message: {
            Text("The modsettings.lsx file has been modified outside this app (possibly by the game). Would you like to restore your last saved load order from backup?")
        }
        .overlay(alignment: .bottom) {
            statusBar
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(SidebarItem.allCases, selection: $selectedSidebarItem) { item in
            Label(item.rawValue, systemImage: item.icon)
                .tag(item)
        }
        .listStyle(.sidebar)
        .frame(minWidth: 180)
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch selectedSidebarItem {
        case .mods:
            ModListView()
        case .profiles:
            ProfileManagerView()
        case .backups:
            BackupManagerView()
        case .scriptExtender:
            SEStatusView()
        case .tools:
            VersionGeneratorView()
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await appState.saveModSettings() }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .help("Save mod order to modsettings.lsx")

            Button {
                Task { await appState.refreshAll() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .help("Rescan mods folder")

            Button {
                appState.launchGame()
            } label: {
                Label("Launch Game", systemImage: "play.fill")
            }
            .help("Launch Baldur's Gate 3")
        }

        ToolbarItem(placement: .navigation) {
            Button {
                appState.launchService.openModsFolder()
            } label: {
                Label("Open Mods Folder", systemImage: "folder")
            }
            .help("Open Mods folder in Finder")
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            if appState.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
            if appState.isExporting {
                ProgressView(value: appState.exportProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                Text("Exporting...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(appState.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let se = appState.seStatus {
                HStack(spacing: 4) {
                    Circle()
                        .fill(se.isInstalled ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(se.isInstalled ? "SE Active" : "SE Not Found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}
