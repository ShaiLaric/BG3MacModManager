import SwiftUI

/// View showing Script Extender (bg3se-macos) installation status and controls.
struct SEStatusView: View {
    @EnvironmentObject var appState: AppState
    @State private var logContent: String?
    @State private var showingLog = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Script Extender (bg3se-macos)")
                    .font(.title2.bold())

                if let status = appState.seStatus {
                    statusCard(status)
                    installationGuide(status)
                    if status.isInstalled {
                        seModsSection
                    }
                    logSection(status)
                } else {
                    ProgressView("Checking status...")
                }
            }
            .padding()
        }
        .onAppear {
            appState.refreshSEStatus()
        }
    }

    // MARK: - Status Card

    private func statusCard(_ status: ScriptExtenderService.SEStatus) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: status.isInstalled ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(status.isInstalled ? .green : .red)

                    VStack(alignment: .leading) {
                        Text(status.isInstalled ? "Script Extender Detected" : "Script Extender Not Found")
                            .font(.headline)
                        Text(status.isDeployed ?
                             "Dylib deployed to game bundle" :
                             "libbg3se.dylib not found in game bundle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if status.isDeployed, let path = status.dylibPath {
                    HStack {
                        Text("Dylib:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(path.path)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        }
    }

    // MARK: - Installation Guide

    @ViewBuilder
    private func installationGuide(_ status: ScriptExtenderService.SEStatus) -> some View {
        if !status.isInstalled {
            GroupBox("Installation Guide") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("bg3se-macos enables Lua-scripted mods on macOS. To install:")
                        .font(.body)

                    guideStep(1, "Clone the repository:",
                              "git clone --recursive https://github.com/tdimino/bg3se-macos.git")
                    guideStep(2, "Build:",
                              "cd bg3se-macos && mkdir -p build && cd build && cmake .. && cmake --build .")
                    guideStep(3, "Deploy the dylib:",
                              "./scripts/deploy.sh")
                    guideStep(4, "Set Steam launch options to:",
                              "/path/to/bg3se-macos/scripts/bg3w.sh %command%")

                    Text("See the bg3se-macos README for full instructions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                .padding(4)
            }
        }
    }

    private func guideStep(_ number: Int, _ text: String, _ code: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(number). \(text)")
                .font(.body)
            Text(code)
                .font(.caption.monospaced())
                .padding(6)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                .textSelection(.enabled)
        }
    }

    // MARK: - SE Mods

    private var seModsSection: some View {
        GroupBox("Script Extender Mods") {
            let seMods = (appState.activeMods + appState.inactiveMods).filter(\.requiresScriptExtender)

            if seMods.isEmpty {
                Text("No SE mods detected")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(4)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(seMods) { mod in
                        HStack {
                            Image(systemName: appState.activeMods.contains(where: { $0.uuid == mod.uuid }) ?
                                  "checkmark.circle.fill" : "circle")
                                .foregroundStyle(appState.activeMods.contains(where: { $0.uuid == mod.uuid }) ?
                                                 .green : .secondary)
                            Text(mod.name)
                                .font(.body)
                            Spacer()
                            Text(appState.activeMods.contains(where: { $0.uuid == mod.uuid }) ? "Active" : "Inactive")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(4)
            }
        }
    }

    // MARK: - Log Section

    @ViewBuilder
    private func logSection(_ status: ScriptExtenderService.SEStatus) -> some View {
        if status.logsAvailable {
            GroupBox("Logs") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("View Latest Log") {
                            logContent = appState.seService.readLatestLog()
                            showingLog = true
                        }
                        .help("Display the most recent SE log inline")
                        Button("Open Logs Folder") {
                            appState.launchService.openSELogs()
                        }
                        .help("Open SE logs folder in Finder")
                    }

                    if showingLog, let content = logContent {
                        ScrollView {
                            Text(content)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(maxHeight: 300)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(4)
            }
        }
    }
}
