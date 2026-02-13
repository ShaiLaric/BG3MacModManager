import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSidebarItem: SidebarItem = .mods
    @State private var isDropTargeted: Bool = false

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
        mainContent
            .overlay(alignment: .bottom) {
                statusBar
            }
            .onDrop(of: Self.acceptedDropTypes, isTargeted: $isDropTargeted) { providers in
                handleFileDrop(providers)
                return true
            }
            .overlay {
                dropTargetOverlay
            }
            .onChange(of: appState.navigateToSidebarItem) { target in
                if let target = target {
                    if target == "scriptExtender" {
                        selectedSidebarItem = .scriptExtender
                    }
                    appState.navigateToSidebarItem = nil
                }
            }
    }

    // MARK: - Main Content (split out to reduce type-checker complexity)

    private var mainContent: some View {
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
        .alert(
            "Activate Imported Mods?",
            isPresented: $appState.showImportActivation
        ) {
            Button("Activate All") {
                for mod in appState.lastImportedMods {
                    appState.activateMod(mod)
                }
                appState.lastImportedMods = []
            }
            Button("Keep Inactive", role: .cancel) {
                appState.lastImportedMods = []
            }
        } message: {
            let names = appState.lastImportedMods.map(\.name).joined(separator: ", ")
            Text("\(appState.lastImportedMods.count) new mod(s) imported: \(names)\n\nWould you like to add them to your active load order?")
        }
    }

    // MARK: - Drop Target Overlay

    @ViewBuilder
    private var dropTargetOverlay: some View {
        if isDropTargeted {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.accentColor, lineWidth: 3)
                    .padding(4)
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 36))
                    Text("Drop to Import Mods")
                        .font(.headline)
                }
                .foregroundStyle(Color.accentColor)
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
            .allowsHitTesting(false)
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
            if appState.isImporting {
                ProgressView()
                    .controlSize(.small)
                Text("Importing...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if appState.isExporting {
                ProgressView(value: appState.exportProgress)
                    .progressViewStyle(.linear)
                    .frame(width: 120)
                    .help("Exporting mod archive to ZIP")
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
                .help(se.isInstalled
                    ? "bg3se-macos is deployed — Script Extender mods will work"
                    : "bg3se-macos not detected — Script Extender mods will not function")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - Drag-and-Drop from Finder

    private static let acceptedDropTypes: [UTType] = {
        var types: [UTType] = [.zip]
        if let pak = UTType(filenameExtension: "pak") { types.append(pak) }
        if let tar = UTType(filenameExtension: "tar") { types.append(tar) }
        if let gz = UTType(filenameExtension: "gz") { types.append(gz) }
        if let tgz = UTType(filenameExtension: "tgz") { types.append(tgz) }
        if let bz2 = UTType(filenameExtension: "bz2") { types.append(bz2) }
        if let xz = UTType(filenameExtension: "xz") { types.append(xz) }
        return types
    }()

    private func handleFileDrop(_ providers: [NSItemProvider]) {
        let group = DispatchGroup()
        let collectQueue = DispatchQueue(label: "bg3mm.drop-url-collector")
        var urls: [URL] = []

        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                group.enter()
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        collectQueue.sync { urls.append(url) }
                    }
                    group.leave()
                }
            }
        }

        group.notify(queue: .main) {
            guard !urls.isEmpty else { return }
            Task {
                await appState.importMods(from: urls)
            }
        }
    }
}
