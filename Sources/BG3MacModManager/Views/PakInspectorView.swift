// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

/// Tool for inspecting the internal contents of a PAK (LSPK) archive file.
struct PakInspectorView: View {
    @State private var selectedURL: URL?
    @State private var header: PakReader.PakHeader?
    @State private var entries: [PakReader.FileEntry] = []
    @State private var errorText: String?
    @State private var searchText = ""
    @State private var showFilePicker = false
    @State private var viewingContent: FileContentItem?

    /// Wrapper for the content viewer sheet.
    struct FileContentItem: Identifiable {
        let id = UUID()
        let name: String
        let content: String
    }

    var body: some View {
        VStack(spacing: 0) {
            // File selection bar
            fileSelectionBar
            Divider()

            if let header = header {
                // Header info bar
                headerInfoBar(header)
                Divider()

                // Quick action buttons
                quickActions
                Divider()

                // File search
                searchField

                // File list
                fileListView
            } else if let error = errorText {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 36))
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "doc.zipper")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Select a PAK file to inspect")
                        .foregroundStyle(.secondary)
                    Button("Open PAK File...") {
                        showFilePicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Choose a .pak file to inspect its contents")
                }
                Spacer()
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [UTType(filenameExtension: "pak") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                loadPak(url)
            }
        }
        .sheet(item: $viewingContent) { item in
            fileContentSheet(item)
        }
    }

    // MARK: - File Selection Bar

    private var fileSelectionBar: some View {
        HStack(spacing: 12) {
            Button("Open PAK File...") {
                showFilePicker = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .help("Choose a .pak file to inspect its contents")

            if let url = selectedURL {
                Image(systemName: "doc.zipper")
                    .foregroundStyle(.secondary)
                Text(url.lastPathComponent)
                    .font(.body.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "arrow.right.circle")
                }
                .buttonStyle(.plain)
                .help("Reveal this PAK file in Finder")
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: - Header Info Bar

    private func headerInfoBar(_ header: PakReader.PakHeader) -> some View {
        HStack(spacing: 16) {
            headerBadge("Version", "\(header.version)")
            headerBadge("Files", "\(entries.count)")
            headerBadge("Priority", "\(header.priority)")
            headerBadge("Flags", String(format: "0x%02X", header.flags))
            if header.isSolid {
                HStack(spacing: 4) {
                    Image(systemName: "cube.fill")
                        .foregroundStyle(.orange)
                    Text("Solid")
                        .font(.caption.bold())
                        .foregroundStyle(.orange)
                }
                .help("This archive uses solid compression — files are compressed together in a single block")
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    private func headerBadge(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospaced().bold())
        }
    }

    // MARK: - Quick Actions

    private var quickActions: some View {
        HStack(spacing: 12) {
            Button {
                viewMetaLsx()
            } label: {
                Label("View meta.lsx", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedURL == nil || !entries.contains { isMetaLsx(path: $0.name) })
            .help("Extract and view the mod's meta.lsx metadata file")

            Button {
                viewInfoJson()
            } label: {
                Label("View info.json", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(selectedURL == nil || !entries.contains { $0.name.hasSuffix("info.json") })
            .help("Extract and view the mod's info.json metadata file")

            Spacer()

            Text("\(filteredEntries.count) file\(filteredEntries.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter files...", text: $searchText)
                .textFieldStyle(.plain)
                .help("Filter the file list by name")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.primary.opacity(0.03))
    }

    // MARK: - File List

    private var filteredEntries: [PakReader.FileEntry] {
        if searchText.isEmpty { return entries }
        let query = searchText.lowercased()
        return entries.filter { $0.name.lowercased().contains(query) }
    }

    private var fileListView: some View {
        List(filteredEntries) { entry in
            HStack {
                Image(systemName: iconForFile(entry.name))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.body.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: 12) {
                        Text(formatBytes(UInt64(entry.uncompressedSize)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if entry.sizeOnDisk != entry.uncompressedSize {
                            Text("\(compressionRatio(entry))% compressed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(compressionLabel(entry.compressionMethod))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .contextMenu {
                Button("View Contents") {
                    viewFileContents(entry)
                }
                .help("Extract and display this file's contents")
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.name, forType: .string)
                }
                .help("Copy the file path within the archive to the clipboard")
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Content Sheet

    private func fileContentSheet(_ item: FileContentItem) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(item.name)
                    .font(.headline.monospaced())
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.content, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Copy file contents to clipboard")
                Button("Done") {
                    viewingContent = nil
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
                .help("Close this viewer")
            }
            .padding()

            Divider()

            ScrollView([.horizontal, .vertical]) {
                Text(item.content)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    // MARK: - Actions

    private func loadPak(_ url: URL) {
        do {
            let result = try PakReader.inspectPak(at: url)
            selectedURL = url
            header = result.header
            entries = result.entries
            errorText = nil
            searchText = ""
        } catch {
            selectedURL = url
            header = nil
            entries = []
            errorText = error.localizedDescription
        }
    }

    private func viewMetaLsx() {
        guard let url = selectedURL else { return }
        do {
            let data = try PakReader.extractMetaLsx(from: url)
            if let text = String(data: data, encoding: .utf8) {
                viewingContent = FileContentItem(name: "meta.lsx", content: text)
            }
        } catch {
            errorText = "Failed to extract meta.lsx: \(error.localizedDescription)"
        }
    }

    private func viewInfoJson() {
        guard let url = selectedURL,
              let infoEntry = entries.first(where: { $0.name.hasSuffix("info.json") }) else { return }
        do {
            let data = try PakReader.extractFile(named: infoEntry.name, from: url)
            if let text = String(data: data, encoding: .utf8) {
                viewingContent = FileContentItem(name: "info.json", content: text)
            }
        } catch {
            errorText = "Failed to extract info.json: \(error.localizedDescription)"
        }
    }

    private func viewFileContents(_ entry: PakReader.FileEntry) {
        guard let url = selectedURL else { return }
        do {
            let data = try PakReader.extractFile(named: entry.name, from: url)
            if let text = String(data: data, encoding: .utf8) {
                viewingContent = FileContentItem(name: entry.name, content: text)
            } else {
                viewingContent = FileContentItem(
                    name: entry.name,
                    content: "[Binary data: \(formatBytes(UInt64(data.count)))]"
                )
            }
        } catch {
            errorText = "Failed to extract \(entry.name): \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func isMetaLsx(path: String) -> Bool {
        let normalized = path.replacingOccurrences(of: "\\", with: "/")
        return normalized.hasPrefix("Mods/") && normalized.hasSuffix("/meta.lsx")
    }

    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "lsx", "xml": return "doc.text"
        case "json": return "curlybraces"
        case "lua": return "chevron.left.forwardslash.chevron.right"
        case "txt", "md": return "doc.plaintext"
        case "png", "jpg", "jpeg", "dds", "tga": return "photo"
        default: return "doc"
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func compressionRatio(_ entry: PakReader.FileEntry) -> Int {
        guard entry.uncompressedSize > 0 else { return 0 }
        return Int(100 - (Double(entry.sizeOnDisk) / Double(entry.uncompressedSize) * 100))
    }

    private func compressionLabel(_ type: PakReader.CompressionType) -> String {
        switch type {
        case .none: return "None"
        case .zlib: return "Zlib"
        case .lz4:  return "LZ4"
        }
    }
}
