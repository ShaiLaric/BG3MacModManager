import Foundation

/// Reads and writes the `modsettings.lsx` file that controls which mods BG3 loads.
///
/// The file has two key sections:
/// - `ModOrder`: ordered list of mod UUIDs (defines load sequence)
/// - `Mods`: `ModuleShortDesc` entries with full metadata per mod
final class ModSettingsService {

    enum ModSettingsError: Error, LocalizedError {
        case fileNotFound
        case parseError(String)
        case writeError(String)

        var errorDescription: String? {
            switch self {
            case .fileNotFound: return "modsettings.lsx not found"
            case .parseError(let msg): return "Failed to parse modsettings.lsx: \(msg)"
            case .writeError(let msg): return "Failed to write modsettings.lsx: \(msg)"
            }
        }
    }

    /// Parsed representation of modsettings.lsx.
    struct ModSettings {
        /// Ordered list of active mod UUIDs (defines load order).
        var modOrder: [String]

        /// Metadata for each active mod, keyed by UUID.
        var mods: [String: ModuleShortDesc]
    }

    struct ModuleShortDesc {
        var folder: String
        var md5: String
        var name: String
        var uuid: String
        var version64: String
    }

    // MARK: - Reading

    /// Read and parse modsettings.lsx from the default location.
    func read() throws -> ModSettings {
        return try read(from: FileLocations.modSettingsFile)
    }

    /// Read and parse modsettings.lsx from a specific URL.
    func read(from url: URL) throws -> ModSettings {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ModSettingsError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        let document = try XMLDocument(data: data)

        return try parseDocument(document)
    }

    private func parseDocument(_ document: XMLDocument) throws -> ModSettings {
        // Parse ModOrder section
        let orderNodes = try document.nodes(forXPath: "//node[@id='ModOrder']/children/node[@id='Module']")
        let modOrder = orderNodes.compactMap { node -> String? in
            guard let element = node as? XMLElement else { return nil }
            return element.attributeElement(id: "UUID")
        }

        // Parse Mods section
        let modNodes = try document.nodes(forXPath: "//node[@id='Mods']/children/node[@id='ModuleShortDesc']")
        var mods: [String: ModuleShortDesc] = [:]

        for node in modNodes {
            guard let element = node as? XMLElement else { continue }
            guard let uuid = element.attributeElement(id: "UUID") else { continue }

            let desc = ModuleShortDesc(
                folder:    element.attributeElement(id: "Folder") ?? "",
                md5:       element.attributeElement(id: "MD5") ?? "",
                name:      element.attributeElement(id: "Name") ?? "",
                uuid:      uuid,
                version64: element.attributeElement(id: "Version64") ?? "36028797018963968"
            )
            mods[uuid] = desc
        }

        return ModSettings(modOrder: modOrder, mods: mods)
    }

    // MARK: - Writing

    /// Write mod settings to the default modsettings.lsx location.
    func write(_ settings: ModSettings) throws {
        try write(settings, to: FileLocations.modSettingsFile)
    }

    /// Write mod settings to a specific URL.
    func write(_ settings: ModSettings, to url: URL) throws {
        let xml = generateXML(settings)

        do {
            let directory = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try xml.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw ModSettingsError.writeError(error.localizedDescription)
        }
    }

    /// Write mod settings using a list of active ModInfo objects (in load order).
    func write(activeMods: [ModInfo]) throws {
        var settings = ModSettings(modOrder: [], mods: [:])

        // Ensure GustavDev is always first
        let gustavDev = ModInfo.gustavDev
        settings.modOrder.append(gustavDev.uuid)
        settings.mods[gustavDev.uuid] = ModuleShortDesc(
            folder: gustavDev.folder,
            md5: gustavDev.md5,
            name: gustavDev.name,
            uuid: gustavDev.uuid,
            version64: String(gustavDev.version64)
        )

        // Add remaining mods in order
        for mod in activeMods where !mod.isBasicGameModule {
            settings.modOrder.append(mod.uuid)
            settings.mods[mod.uuid] = ModuleShortDesc(
                folder: mod.folder,
                md5: mod.md5,
                name: mod.name,
                uuid: mod.uuid,
                version64: String(mod.version64)
            )
        }

        try write(settings)
    }

    // MARK: - XML Generation

    private func generateXML(_ settings: ModSettings) -> String {
        var xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <save>
          <version major="4" minor="7" revision="1" build="3"/>
          <region id="ModuleSettings">
            <node id="root">
              <children>
                <node id="ModOrder">
                  <children>

        """

        for uuid in settings.modOrder {
            xml += """
                            <node id="Module">
                              <attribute id="UUID" value="\(uuid)" type="FixedString"/>
                            </node>\n
            """
        }

        xml += """
                  </children>
                </node>
                <node id="Mods">
                  <children>

        """

        // Write mods in the same order as modOrder, then any extras
        let orderedUUIDs = settings.modOrder + settings.mods.keys.filter { !settings.modOrder.contains($0) }

        for uuid in orderedUUIDs {
            guard let mod = settings.mods[uuid] else { continue }
            xml += """
                            <node id="ModuleShortDesc">
                              <attribute id="Folder" value="\(escapeXML(mod.folder))" type="LSString"/>
                              <attribute id="MD5" value="\(escapeXML(mod.md5))" type="LSString"/>
                              <attribute id="Name" value="\(escapeXML(mod.name))" type="LSString"/>
                              <attribute id="UUID" value="\(mod.uuid)" type="FixedString"/>
                              <attribute id="Version64" value="\(mod.version64)" type="int64"/>
                            </node>\n
            """
        }

        xml += """
                  </children>
                </node>
              </children>
            </node>
          </region>
        </save>
        """

        return xml
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

// MARK: - XMLElement Extension for BG3 Attribute Parsing

private extension XMLElement {
    /// Extracts the `value` from a child `<attribute id="..." value="..."/>` element.
    func attributeElement(id: String) -> String? {
        guard let children = self.children else { return nil }
        for child in children {
            guard let element = child as? XMLElement,
                  element.name == "attribute",
                  let attrId = element.attribute(forName: "id")?.stringValue,
                  attrId == id else { continue }
            return element.attribute(forName: "value")?.stringValue
        }
        return nil
    }
}
