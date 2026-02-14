// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Exports active mod lists to various text formats (CSV, Markdown, plain text).
final class TextExportService {

    enum ExportFormat: String, CaseIterable, Identifiable {
        case csv = "CSV"
        case markdown = "Markdown"
        case plainText = "Plain Text"

        var id: String { rawValue }

        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .markdown: return "md"
            case .plainText: return "txt"
            }
        }
    }

    /// Generate a text representation of the active mod list in the specified format.
    func export(activeMods: [ModInfo], format: ExportFormat) -> String {
        switch format {
        case .csv: return exportCSV(mods: activeMods)
        case .markdown: return exportMarkdown(mods: activeMods)
        case .plainText: return exportPlainText(mods: activeMods)
        }
    }

    // MARK: - CSV (RFC 4180)

    private func exportCSV(mods: [ModInfo]) -> String {
        var lines: [String] = []
        lines.append(csvRow([
            "Position", "Name", "Author", "UUID", "Folder",
            "Version", "Version64", "Tags", "Requires SE", "PAK File"
        ]))

        for (index, mod) in mods.enumerated() {
            let version = Version64(rawValue: mod.version64).description
            lines.append(csvRow([
                "\(index + 1)",
                mod.name,
                mod.author,
                mod.uuid,
                mod.folder,
                version,
                "\(mod.version64)",
                mod.tags.joined(separator: "; "),
                mod.requiresScriptExtender ? "Yes" : "No",
                mod.pakFileName ?? ""
            ]))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    /// Produce a single CSV row, quoting fields that contain special characters.
    private func csvRow(_ fields: [String]) -> String {
        fields.map { csvEscape($0) }.joined(separator: ",")
    }

    /// RFC 4180 escaping: double-quote fields containing commas, quotes, or newlines.
    private func csvEscape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    // MARK: - Markdown

    private func exportMarkdown(mods: [ModInfo]) -> String {
        var lines: [String] = []
        lines.append("# Mod Load Order")
        lines.append("")
        lines.append("| # | Name | Author | Version | Tags | Requires SE |")
        lines.append("|---|------|--------|---------|------|-------------|")

        for (index, mod) in mods.enumerated() {
            let version = Version64(rawValue: mod.version64).description
            let tags = mod.tags.joined(separator: ", ")
            let se = mod.requiresScriptExtender ? "Yes" : "No"
            // Escape pipe characters in field values
            let name = mod.name.replacingOccurrences(of: "|", with: "\\|")
            let author = mod.author.replacingOccurrences(of: "|", with: "\\|")
            lines.append("| \(index + 1) | \(name) | \(author) | \(version) | \(tags) | \(se) |")
        }

        lines.append("")
        lines.append("---")
        lines.append("**Total:** \(mods.count) active mod\(mods.count == 1 ? "" : "s")  ")
        lines.append("**Exported:** \(formattedTimestamp())")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Plain Text

    private func exportPlainText(mods: [ModInfo]) -> String {
        var lines: [String] = []
        lines.append("Mod Load Order")
        lines.append("==============")
        lines.append("")

        for (index, mod) in mods.enumerated() {
            let version = Version64(rawValue: mod.version64).description
            lines.append("\(index + 1). \(mod.name) (v\(version)) by \(mod.author)")
            var details: [String] = ["UUID: \(mod.uuid)", "Folder: \(mod.folder)"]
            if !mod.tags.isEmpty {
                details.append("Tags: \(mod.tags.joined(separator: ", "))")
            }
            if mod.requiresScriptExtender {
                details.append("Requires SE")
            }
            lines.append("   \(details.joined(separator: "  |  "))")
        }

        lines.append("")
        lines.append("---")
        lines.append("Total: \(mods.count) active mod\(mods.count == 1 ? "" : "s")")
        lines.append("Exported: \(formattedTimestamp())")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Helpers

    private func formattedTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .short
        return formatter.string(from: Date())
    }
}
