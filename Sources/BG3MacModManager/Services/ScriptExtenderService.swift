import Foundation

/// Detects and manages bg3se-macos (Script Extender for macOS) integration.
final class ScriptExtenderService {

    struct SEStatus {
        var isInstalled: Bool
        var isDeployed: Bool
        var dylibPath: URL?
        var logsAvailable: Bool
        var latestLogPath: URL?
    }

    // MARK: - Detection

    /// Check the current Script Extender installation status.
    func checkStatus() -> SEStatus {
        let fm = FileManager.default

        // Check deployed dylib in game app bundle
        let deployedPath = FileLocations.seDeployedDylib
        let isDeployed = fm.fileExists(atPath: deployedPath.path)

        // Check logs directory
        let logsDir = FileLocations.seLogsDirectory
        let logsExist = fm.fileExists(atPath: logsDir.path)

        // Check latest log
        let latestLog = FileLocations.seLatestLog
        let latestLogExists = fm.fileExists(atPath: latestLog.path)

        // Also check if SE data directory exists (created on first run)
        let seDataDir = FileLocations.seDataDirectory
        let seDataExists = fm.fileExists(atPath: seDataDir.path)

        return SEStatus(
            isInstalled: isDeployed || seDataExists,
            isDeployed: isDeployed,
            dylibPath: isDeployed ? deployedPath : nil,
            logsAvailable: logsExist && latestLogExists,
            latestLogPath: latestLogExists ? latestLog : nil
        )
    }

    /// Read the latest SE log file contents.
    func readLatestLog(maxBytes: Int = 100_000) -> String? {
        let logPath = FileLocations.seLatestLog
        guard FileManager.default.fileExists(atPath: logPath.path),
              let data = try? Data(contentsOf: logPath) else {
            return nil
        }

        let readData: Data
        if data.count > maxBytes {
            readData = data[(data.count - maxBytes)...]
        } else {
            readData = data
        }

        return String(data: readData, encoding: .utf8)
    }

    /// Check if a specific mod requires the Script Extender.
    func modRequiresScriptExtender(pakURL: URL) -> Bool {
        PakReader.containsScriptExtender(at: pakURL)
    }

    // MARK: - SE Environment Variables

    /// Environment variables that can be passed to bg3se-macos via the launch wrapper.
    enum SEEnvironmentVar: String, CaseIterable {
        case noHooks  = "BG3SE_NO_HOOKS"
        case noNet    = "BG3SE_NO_NET"
        case minimal  = "BG3SE_MINIMAL"

        var description: String {
            switch self {
            case .noHooks:  return "Disable function hooks (debugging)"
            case .noNet:    return "Disable networking features"
            case .minimal:  return "Minimal mode (reduced functionality)"
            }
        }
    }

    /// Build the environment dictionary for launching with SE.
    func buildEnvironment(noHooks: Bool = false, noNet: Bool = false, minimal: Bool = false) -> [String: String] {
        var env: [String: String] = [:]
        if noHooks { env[SEEnvironmentVar.noHooks.rawValue] = "1" }
        if noNet   { env[SEEnvironmentVar.noNet.rawValue]   = "1" }
        if minimal { env[SEEnvironmentVar.minimal.rawValue] = "1" }
        return env
    }

    // MARK: - Deployment State Persistence

    /// Record that SE is currently deployed (call when SE is detected as deployed).
    func recordDeployed() {
        do {
            try FileLocations.ensureDirectoryExists(FileLocations.appSupportDirectory)
            let data = try JSONEncoder().encode(["wasDeployed": true])
            try data.write(to: FileLocations.seDeployedFlagFile, options: .atomic)
        } catch {
            // Non-fatal
        }
    }

    /// Clear the deployed flag (call when user acknowledges disappearance or SE is reinstalled).
    func clearDeployedFlag() {
        try? FileManager.default.removeItem(at: FileLocations.seDeployedFlagFile)
    }

    /// Check if SE was previously recorded as deployed.
    func wasDeployed() -> Bool {
        guard let data = try? Data(contentsOf: FileLocations.seDeployedFlagFile),
              let dict = try? JSONDecoder().decode([String: Bool].self, from: data) else {
            return false
        }
        return dict["wasDeployed"] ?? false
    }
}
