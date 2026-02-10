import Foundation

/// Discovers mods by scanning the Mods folder and parsing metadata from
/// `info.json` files, `meta.lsx` inside `.pak` archives, or filenames.
final class ModDiscoveryService {

    private let modSettingsService = ModSettingsService()

    /// Discover all mods in the Mods directory.
    func discoverMods() throws -> [ModInfo] {
        let modsFolder = FileLocations.modsFolder

        guard FileManager.default.fileExists(atPath: modsFolder.path) else {
            return []
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: modsFolder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )

        // Find all .pak files
        let pakFiles = contents.filter { $0.pathExtension.lowercased() == "pak" }

        var discoveredMods: [ModInfo] = []

        for pakURL in pakFiles {
            if let mod = discoverMod(pakURL: pakURL, allFiles: contents) {
                discoveredMods.append(mod)
            }
        }

        return discoveredMods
    }

    /// Discover mods and merge with current modsettings.lsx to determine active state.
    func discoverModsWithState() throws -> (active: [ModInfo], inactive: [ModInfo]) {
        let allMods = try discoverMods()

        // Read current modsettings.lsx
        let currentSettings: ModSettingsService.ModSettings?
        do {
            currentSettings = try modSettingsService.read()
        } catch {
            currentSettings = nil
        }

        guard let settings = currentSettings else {
            // No modsettings.lsx: all mods are inactive
            return (active: [], inactive: allMods)
        }

        var active: [ModInfo] = []
        var inactiveSet = Set(allMods.map { $0.uuid })

        // Build active list in the order defined by ModOrder
        for uuid in settings.modOrder {
            if uuid == Constants.gustavDevUUID { continue }

            if let mod = allMods.first(where: { $0.uuid == uuid }) {
                active.append(mod)
                inactiveSet.remove(uuid)
            } else if let desc = settings.mods[uuid] {
                // Mod is in modsettings but .pak not found - create entry from settings
                let mod = ModInfo(
                    uuid: desc.uuid,
                    folder: desc.name,
                    name: desc.name,
                    author: "Unknown",
                    modDescription: "",
                    version64: Int64(desc.version64) ?? 36028797018963968,
                    md5: desc.md5,
                    tags: [],
                    dependencies: [],
                    requiresScriptExtender: false,
                    pakFileName: nil,
                    pakFilePath: nil,
                    metadataSource: .modSettings
                )
                active.append(mod)
            }
        }

        let inactive = allMods.filter { inactiveSet.contains($0.uuid) }

        return (active: active, inactive: inactive)
    }

    // MARK: - Single Mod Discovery

    private func discoverMod(pakURL: URL, allFiles: [URL]) -> ModInfo? {
        let pakFilename = pakURL.lastPathComponent
        let baseName = pakURL.deletingPathExtension().lastPathComponent

        // Strategy 1: Look for info.json alongside the .pak
        let infoJsonURL = pakURL.deletingLastPathComponent().appendingPathComponent("info.json")
        if let mod = parseInfoJson(at: infoJsonURL, pakFilename: pakFilename, pakURL: pakURL) {
            return mod
        }

        // Also check for <modname>.json
        let namedJsonURL = pakURL.deletingLastPathComponent().appendingPathComponent("\(baseName).json")
        if let mod = parseInfoJson(at: namedJsonURL, pakFilename: pakFilename, pakURL: pakURL) {
            return mod
        }

        // Strategy 2: Extract meta.lsx from inside the .pak
        if let mod = parseMetaLsx(from: pakURL, pakFilename: pakFilename) {
            return mod
        }

        // Strategy 3: Fall back to filename-based detection
        return ModInfo.fromPakFilename(pakFilename, at: pakURL)
    }

    // MARK: - info.json Parsing

    private func parseInfoJson(at url: URL, pakFilename: String, pakURL: URL) -> ModInfo? {
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        struct InfoJsonRoot: Decodable {
            let mods: [InfoJsonMod]?
            // Some info.json formats use "Mods" instead of "mods"
            enum CodingKeys: String, CodingKey {
                case mods
                case Mods
            }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let mods = try? container.decode([InfoJsonMod].self, forKey: .mods) {
                    self.mods = mods
                } else {
                    self.mods = try? container.decode([InfoJsonMod].self, forKey: .Mods)
                }
            }
        }

        struct InfoJsonMod: Decodable {
            let modName: String?
            let folderName: String?
            let UUID: String?
            let version: String?
            let MD5: String?
            let Name: String?
            let Folder: String?
            let Author: String?
            let Description: String?

            // Flexible decoding for different naming conventions
            enum CodingKeys: String, CodingKey {
                case modName, folderName, UUID, version, MD5
                case Name, Folder, Author, Description
            }
        }

        guard let root = try? JSONDecoder().decode(InfoJsonRoot.self, from: data),
              let modEntry = root.mods?.first else {
            return nil
        }

        let uuid = modEntry.UUID ?? UUID().uuidString.lowercased()
        let name = modEntry.modName ?? modEntry.Name ?? pakFilename.replacingOccurrences(of: ".pak", with: "")
        let folder = modEntry.folderName ?? modEntry.Folder ?? name

        let version64: Int64
        if let versionStr = modEntry.version, let v = Version64(versionString: versionStr) {
            version64 = v.rawValue
        } else {
            version64 = Version64(major: 1).rawValue
        }

        let requiresSE = PakReader.containsScriptExtender(at: pakURL)

        return ModInfo(
            uuid: uuid,
            folder: folder,
            name: name,
            author: modEntry.Author ?? "Unknown",
            modDescription: modEntry.Description ?? "",
            version64: version64,
            md5: modEntry.MD5 ?? "",
            tags: [],
            dependencies: [],
            requiresScriptExtender: requiresSE,
            pakFileName: pakFilename,
            pakFilePath: pakURL,
            metadataSource: .infoJson
        )
    }

    // MARK: - meta.lsx Parsing (from inside .pak)

    private func parseMetaLsx(from pakURL: URL, pakFilename: String) -> ModInfo? {
        guard let metaData = try? PakReader.extractMetaLsx(from: pakURL),
              let document = try? XMLDocument(data: metaData) else {
            return nil
        }

        // Parse ModuleInfo
        guard let moduleInfoNodes = try? document.nodes(forXPath: "//node[@id='ModuleInfo']"),
              let moduleInfo = moduleInfoNodes.first as? XMLElement else {
            return nil
        }

        let uuid = moduleInfo.lsxAttribute("UUID") ?? UUID().uuidString.lowercased()
        let folder = moduleInfo.lsxAttribute("Folder") ?? pakFilename.replacingOccurrences(of: ".pak", with: "")
        let name = moduleInfo.lsxAttribute("Name") ?? folder
        let author = moduleInfo.lsxAttribute("Author") ?? "Unknown"
        let description = moduleInfo.lsxAttribute("Description") ?? ""
        let version64Str = moduleInfo.lsxAttribute("Version64") ?? "36028797018963968"
        let md5 = moduleInfo.lsxAttribute("MD5") ?? ""
        let tagsStr = moduleInfo.lsxAttribute("Tags") ?? ""
        let tags = tagsStr.split(separator: ";").map(String.init)

        // Parse Dependencies
        var dependencies: [ModDependency] = []
        if let depNodes = try? document.nodes(forXPath: "//node[@id='Dependencies']/children/node[@id='ModuleShortDesc']") {
            for node in depNodes {
                guard let elem = node as? XMLElement,
                      let depUUID = elem.lsxAttribute("UUID") else { continue }
                dependencies.append(ModDependency(
                    uuid: depUUID,
                    folder: elem.lsxAttribute("Folder") ?? "",
                    name: elem.lsxAttribute("Name") ?? "",
                    version64: Int64(elem.lsxAttribute("Version64") ?? "0") ?? 0,
                    md5: elem.lsxAttribute("MD5") ?? ""
                ))
            }
        }

        let requiresSE = PakReader.containsScriptExtender(at: pakURL)

        return ModInfo(
            uuid: uuid,
            folder: folder,
            name: name,
            author: author,
            modDescription: description,
            version64: Int64(version64Str) ?? Version64(major: 1).rawValue,
            md5: md5,
            tags: tags,
            dependencies: dependencies,
            requiresScriptExtender: requiresSE,
            pakFileName: pakFilename,
            pakFilePath: pakURL,
            metadataSource: .metaLsx
        )
    }
}

// MARK: - XMLElement Extension

private extension XMLElement {
    /// Extract value from `<attribute id="..." value="..."/>` child element (meta.lsx format).
    func lsxAttribute(_ id: String) -> String? {
        guard let children = self.children else { return nil }
        for child in children {
            guard let element = child as? XMLElement,
                  element.name == "attribute",
                  element.attribute(forName: "id")?.stringValue == id else { continue }
            return element.attribute(forName: "value")?.stringValue
        }
        return nil
    }
}
