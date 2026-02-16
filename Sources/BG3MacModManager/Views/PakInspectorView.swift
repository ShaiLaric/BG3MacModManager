// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import UniformTypeIdentifiers

/// Tool for inspecting the internal contents of a PAK (LSPK) archive file.
/// Supports opening .pak files directly or .zip archives containing a PAK.
struct PakInspectorView: View {
    /// URL of the PAK file being inspected (may be inside a temp dir if extracted from ZIP).
    @State private var selectedURL: URL?
    /// The original file the user selected (could be .pak or .zip).
    @State private var sourceURL: URL?
    @State private var header: PakReader.PakHeader?
    @State private var entries: [PakReader.FileEntry] = []
    @State private var errorText: String?
    @State private var searchText = ""
    @State private var viewingContent: FileContentItem?

    /// Temporary directory holding extracted ZIP contents; cleaned up on new load or disappear.
    @State private var tempExtractionDir: URL?
    /// info.json content found alongside the PAK in the ZIP (not inside the PAK).
    @State private var zipInfoJsonContent: String?
    /// Whether to show the PAK picker when a ZIP contains multiple PAKs.
    @State private var showPakPicker = false
    /// PAK files found in the current ZIP (for the picker).
    @State private var availablePaks: [URL] = []

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
                    Text("Select a PAK or ZIP file to inspect")
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        Button("Select File\u{2026}") {
                            selectFilePicker()
                        }
                        .buttonStyle(.borderedProminent)
                        .help("Select a .pak or .zip file \u{2014} ZIP files are opened automatically to find the PAK inside")
                        Button("Browse ZIP\u{2026}") {
                            browseZipPicker()
                        }
                        .buttonStyle(.bordered)
                        .help("Browse inside a ZIP archive to select a specific .pak file")
                    }
                }
                Spacer()
            }
        }
        .sheet(item: $viewingContent) { item in
            fileContentSheet(item)
        }
        .sheet(isPresented: $showPakPicker) {
            pakPickerSheet
        }
        .onDisappear {
            cleanupTempDir()
        }
    }

    // MARK: - File Selection Bar

    private var fileSelectionBar: some View {
        HStack(spacing: 12) {
            Button("Select File\u{2026}") {
                selectFilePicker()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .help("Select a .pak or .zip file \u{2014} ZIP files are opened automatically to find the PAK inside")

            Button("Browse ZIP\u{2026}") {
                browseZipPicker()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Browse inside a ZIP archive to select a specific .pak file")

            if let url = sourceURL {
                Image(systemName: url.pathExtension.lowercased() == "zip" ? "doc.zipper" : "doc.zipper")
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.body.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    if let pakURL = selectedURL, pakURL.absoluteString != url.absoluteString {
                        Text(pakURL.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Image(systemName: "arrow.right.circle")
                }
                .buttonStyle(.plain)
                .help("Reveal this file in Finder")
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

            if zipInfoJsonContent != nil {
                Button {
                    if let content = zipInfoJsonContent {
                        viewingContent = FileContentItem(name: "info.json (from ZIP)", content: content)
                    }
                } label: {
                    Label("View info.json (ZIP)", systemImage: "curlybraces")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("View the info.json metadata file found alongside the PAK in the ZIP archive")
            }

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

    // MARK: - PAK Picker Sheet

    private var pakPickerSheet: some View {
        VStack(spacing: 12) {
            Text("Multiple PAK Files Found")
                .font(.headline)
            Text("This ZIP contains \(availablePaks.count) PAK files. Choose which one to inspect:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List(availablePaks, id: \.absoluteString) { pakURL in
                Button {
                    showPakPicker = false
                    loadPak(pakURL, isFromZip: true)
                } label: {
                    HStack {
                        Image(systemName: "doc.zipper")
                        Text(pakURL.lastPathComponent)
                            .font(.body.monospaced())
                        Spacer()
                        if let attrs = try? FileManager.default.attributesOfItem(atPath: pakURL.path),
                           let size = attrs[.size] as? UInt64 {
                            Text(formatBytes(size))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .frame(minHeight: 150, maxHeight: 300)

            Button("Cancel") {
                showPakPicker = false
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            .help("Close without selecting a PAK file")
        }
        .padding()
        .frame(minWidth: 400)
    }

    // MARK: - File Pickers

    /// Select a PAK or ZIP file as-is. ZIPs are auto-extracted to find the PAK inside.
    private func selectFilePicker() {
        let panel = NSOpenPanel()
        panel.title = "Select PAK or ZIP File"
        panel.prompt = "Select"
        panel.allowedContentTypes = [
            UTType(filenameExtension: "pak") ?? .data,
            UTType(filenameExtension: "zip") ?? .data,
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        handleSelectedFile(url)
    }

    /// Browse into a ZIP archive to pick a specific PAK file from inside it.
    private func browseZipPicker() {
        let panel = NSOpenPanel()
        panel.title = "Browse ZIP for PAK File"
        panel.allowedContentTypes = [UTType(filenameExtension: "pak") ?? .data]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        cleanupTempDir()
        loadPak(url)
    }

    private func handleSelectedFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "zip" {
            loadZip(url)
        } else {
            cleanupTempDir()
            loadPak(url)
        }
    }

    // MARK: - Actions

    private func loadPak(_ url: URL, isFromZip: Bool = false) {
        do {
            let result = try PakReader.inspectPak(at: url)
            selectedURL = url
            if !isFromZip {
                sourceURL = url
                zipInfoJsonContent = nil
            }
            header = result.header
            entries = result.entries
            errorText = nil
            searchText = ""
        } catch {
            selectedURL = url
            if !isFromZip { sourceURL = url }
            header = nil
            entries = []
            errorText = error.localizedDescription
        }
    }

    private func loadZip(_ url: URL) {
        cleanupTempDir()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PakInspector-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let archiveService = ArchiveService()
            try archiveService.extract(archive: url, to: tempDir)
        } catch {
            sourceURL = url
            selectedURL = nil
            header = nil
            entries = []
            errorText = "Failed to extract ZIP: \(error.localizedDescription)"
            return
        }

        tempExtractionDir = tempDir

        // Find all PAK files and the first info.json recursively
        var pakFiles: [URL] = []
        var infoJsonURL: URL?
        if let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil) {
            while let fileURL = enumerator.nextObject() as? URL {
                if fileURL.pathExtension.lowercased() == "pak" {
                    pakFiles.append(fileURL)
                } else if fileURL.lastPathComponent.lowercased() == "info.json" && infoJsonURL == nil {
                    infoJsonURL = fileURL
                }
            }
        }

        // Load ZIP-level info.json if found
        if let jsonURL = infoJsonURL,
           let data = try? Data(contentsOf: jsonURL),
           let text = String(data: data, encoding: .utf8) {
            zipInfoJsonContent = text
        } else {
            zipInfoJsonContent = nil
        }

        sourceURL = url

        if pakFiles.isEmpty {
            selectedURL = nil
            header = nil
            entries = []
            errorText = "No .pak files found in this ZIP archive."
        } else if pakFiles.count == 1 {
            loadPak(pakFiles[0], isFromZip: true)
        } else {
            // Multiple PAKs — show picker
            availablePaks = pakFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }
            showPakPicker = true
        }
    }

    private func cleanupTempDir() {
        if let dir = tempExtractionDir {
            try? FileManager.default.removeItem(at: dir)
            tempExtractionDir = nil
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
