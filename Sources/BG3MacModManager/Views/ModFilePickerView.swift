// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Custom file picker sheet that replaces NSOpenPanel for cases where ZIP files
/// must be selectable as opaque files (not navigable). macOS NSOpenPanel treats
/// ZIPs as transparent directories and no API can prevent browsing into them.
struct ModFilePickerView: View {
    /// Title shown at the top of the picker.
    let title: String
    /// Label for the confirm button ("Import" or "Select").
    let prompt: String
    /// File extensions to show (e.g. ["pak", "zip", "tar"]).
    let allowedExtensions: Set<String>
    /// Whether the user can select more than one file.
    let allowsMultipleSelection: Bool
    /// Called with the selected file URL(s) when the user confirms.
    let onSelect: ([URL]) -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("lastFilePickerDirectory") private var lastDirectory: String = ""

    @State private var currentDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    @State private var contents: [FileItem] = []
    @State private var selectedFiles: Set<URL> = []
    @State private var errorMessage: String?

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider()
            navigationBar
            Divider()
            fileList
            Divider()
            actionBar
        }
        .frame(minWidth: 600, idealWidth: 700, minHeight: 450, idealHeight: 550)
        .onAppear {
            if !lastDirectory.isEmpty,
               FileManager.default.fileExists(atPath: lastDirectory) {
                currentDirectory = URL(fileURLWithPath: lastDirectory)
            } else {
                let downloads = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Downloads")
                if FileManager.default.fileExists(atPath: downloads.path) {
                    currentDirectory = downloads
                }
            }
            loadDirectory()
        }
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    navigateUp()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(currentDirectory.path == "/")
                .help("Go to parent directory")

                Text(abbreviatedPath(currentDirectory))
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()
            }
            .padding(.horizontal)

            // Quick-access buttons
            HStack(spacing: 6) {
                Text("Quick Access:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                quickAccessButton("Downloads", systemImage: "arrow.down.circle",
                                  url: FileManager.default.homeDirectoryForCurrentUser
                                      .appendingPathComponent("Downloads"))
                quickAccessButton("Desktop", systemImage: "menubar.dock.rectangle",
                                  url: FileManager.default.homeDirectoryForCurrentUser
                                      .appendingPathComponent("Desktop"))
                quickAccessButton("Home", systemImage: "house",
                                  url: FileManager.default.homeDirectoryForCurrentUser)
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 6)
    }

    private func quickAccessButton(_ label: String, systemImage: String, url: URL) -> some View {
        Button {
            navigateTo(url)
        } label: {
            Label(label, systemImage: systemImage)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(!FileManager.default.fileExists(atPath: url.path))
        .help("Go to \(label)")
    }

    // MARK: - File List

    @ViewBuilder
    private var fileList: some View {
        if let error = errorMessage {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 32))
                    .foregroundStyle(.red)
                Text(error)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding()
            Spacer()
        } else if contents.isEmpty {
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "folder")
                    .font(.system(size: 32))
                    .foregroundStyle(.secondary)
                Text("No matching files in this directory")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        } else {
            List {
                ForEach(contents) { item in
                    if item.isDirectory {
                        directoryRow(item)
                    } else {
                        fileRow(item)
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private func directoryRow(_ item: FileItem) -> some View {
        Button {
            navigateTo(item.url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                Text(item.name)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func fileRow(_ item: FileItem) -> some View {
        let isSelected = selectedFiles.contains(item.url)
        return Button {
            toggleSelection(item.url)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .frame(width: 20)
                Image(systemName: iconForExtension(item.url.pathExtension.lowercased()))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(item.name)
                    .lineLimit(1)
                Spacer()
                Text(formatBytes(item.fileSize))
                    .foregroundStyle(.secondary)
                    .font(.caption)
                if let date = item.modDate {
                    Text(formatDate(date))
                        .foregroundStyle(.tertiary)
                        .font(.caption)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .help("Cancel file selection")

            Spacer()

            if !selectedFiles.isEmpty {
                Text("\(selectedFiles.count) selected")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Button(prompt) {
                lastDirectory = currentDirectory.path
                onSelect(Array(selectedFiles))
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(selectedFiles.isEmpty)
            .help("\(prompt) the selected file\(selectedFiles.count == 1 ? "" : "s")")
        }
        .padding()
    }

    // MARK: - Navigation

    private func navigateTo(_ url: URL) {
        currentDirectory = url
        loadDirectory()
    }

    private func navigateUp() {
        let parent = currentDirectory.deletingLastPathComponent()
        if parent.path != currentDirectory.path {
            currentDirectory = parent
            loadDirectory()
        }
    }

    // MARK: - Selection

    private func toggleSelection(_ url: URL) {
        if allowsMultipleSelection {
            if selectedFiles.contains(url) {
                selectedFiles.remove(url)
            } else {
                selectedFiles.insert(url)
            }
        } else {
            // Single-select mode: toggle or replace
            if selectedFiles.contains(url) {
                selectedFiles.removeAll()
            } else {
                selectedFiles = [url]
            }
        }
    }

    // MARK: - Directory Loading

    private func loadDirectory() {
        selectedFiles.removeAll()
        do {
            let keys: Set<URLResourceKey> = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
            let items = try FileManager.default.contentsOfDirectory(
                at: currentDirectory,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )
            contents = items.compactMap { url -> FileItem? in
                let values = try? url.resourceValues(forKeys: keys)
                let isDir = values?.isDirectory ?? false
                // Hide non-matching files (but always show directories)
                if !isDir && !allowedExtensions.contains(url.pathExtension.lowercased()) {
                    return nil
                }
                return FileItem(
                    url: url,
                    name: url.lastPathComponent,
                    isDirectory: isDir,
                    fileSize: Int64(values?.fileSize ?? 0),
                    modDate: values?.contentModificationDate
                )
            }.sorted()
            errorMessage = nil
        } catch {
            contents = []
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func abbreviatedPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext {
        case "pak": return "doc.zipper"
        case "zip": return "doc.zipper"
        case "tar", "gz", "tgz", "bz2", "xz": return "archivebox"
        default: return "doc"
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - FileItem

extension ModFilePickerView {
    struct FileItem: Identifiable, Comparable {
        let url: URL
        let name: String
        let isDirectory: Bool
        let fileSize: Int64
        let modDate: Date?

        var id: URL { url }

        static func < (lhs: FileItem, rhs: FileItem) -> Bool {
            // Directories first, then alphabetical by name (case-insensitive)
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}
