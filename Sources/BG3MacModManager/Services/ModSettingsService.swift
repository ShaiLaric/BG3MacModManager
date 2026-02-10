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

        // Ensure base game module (GustavX) is always first
        let baseModule = ModInfo.baseGameModule
        settings.modOrder.append(baseModule.uuid)
        settings.mods[baseModule.uuid] = ModuleShortDesc(
            folder: baseModule.folder,
            md5: baseModule.md5,
            name: baseModule.name,
            uuid: baseModule.uuid,
            version64: String(baseModule.version64)
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
        let i1 = "    "      // 1 level indent
        let i2 = "        "  // 2 levels
        let i3 = "            " // 3 levels
        let i4 = "                " // 4 levels
        let i5 = "                    " // 5 levels
        let i6 = "                        " // 6 levels

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")
        lines.append("<save>")
        lines.append("\(i1)<version major=\"4\" minor=\"8\" revision=\"0\" build=\"500\"/>")
        lines.append("\(i1)<region id=\"ModuleSettings\">")
        lines.append("\(i2)<node id=\"root\">")
        lines.append("\(i3)<children>")

        // ModOrder section
        lines.append("\(i4)<node id=\"ModOrder\">")
        lines.append("\(i5)<children>")
        for uuid in settings.modOrder {
            lines.append("\(i6)<node id=\"Module\">")
            lines.append("\(i6)    <attribute id=\"UUID\" type=\"guid\" value=\"\(uuid)\"/>")
            lines.append("\(i6)</node>")
        }
        lines.append("\(i5)</children>")
        lines.append("\(i4)</node>")

        // Mods section
        lines.append("\(i4)<node id=\"Mods\">")
        lines.append("\(i5)<children>")

        let orderedUUIDs = settings.modOrder + settings.mods.keys.filter { !settings.modOrder.contains($0) }

        for uuid in orderedUUIDs {
            guard let mod = settings.mods[uuid] else { continue }
            lines.append("\(i6)<node id=\"ModuleShortDesc\">")
            lines.append("\(i6)    <attribute id=\"Folder\" type=\"LSString\" value=\"\(escapeXML(mod.folder))\"/>")
            lines.append("\(i6)    <attribute id=\"MD5\" type=\"LSString\" value=\"\(escapeXML(mod.md5))\"/>")
            lines.append("\(i6)    <attribute id=\"Name\" type=\"LSString\" value=\"\(escapeXML(mod.name))\"/>")
            lines.append("\(i6)    <attribute id=\"PublishHandle\" type=\"uint64\" value=\"0\"/>")
            lines.append("\(i6)    <attribute id=\"UUID\" type=\"guid\" value=\"\(mod.uuid)\"/>")
            lines.append("\(i6)    <attribute id=\"Version64\" type=\"int64\" value=\"\(mod.version64)\"/>")
            lines.append("\(i6)</node>")
        }

        lines.append("\(i5)</children>")
        lines.append("\(i4)</node>")
        lines.append("\(i3)</children>")
        lines.append("\(i2)</node>")
        lines.append("\(i1)</region>")
        lines.append("</save>")

        return lines.joined(separator: "\n")
    }

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
