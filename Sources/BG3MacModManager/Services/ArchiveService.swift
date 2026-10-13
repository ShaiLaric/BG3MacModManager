// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Darwin
import ZIPFoundation

/// Handles extraction of various archive formats (ZIP, tar variants) and ZIP creation.
struct ArchiveService: Sendable {
    var maximumExpandedBytes: UInt64 = 8 * 1_024 * 1_024 * 1_024
    var maximumEntries: Int = 100_000

    enum ArchiveError: Error, LocalizedError {
        case unsupportedFormat(String)
        case extractionFailed(String)
        case zipCreationFailed(String)
        case unsafeEntry(String)
        case archiveTooLarge

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext):
                return "Unsupported archive format: \(ext)"
            case .extractionFailed(let msg):
                return "Archive extraction failed: \(msg)"
            case .zipCreationFailed(let msg):
                return "Failed to create ZIP archive: \(msg)"
            case .unsafeEntry(let path):
                return "Archive contains an unsafe path or link: \(path)"
            case .archiveTooLarge:
                return "Archive exceeds the extraction safety limit"
            }
        }
    }

    enum ArchiveFormat {
        case zip
        case tar
        case tarGz
        case tarBz2
        case tarXz

        init?(pathExtension: String, fullFilename: String) {
            let ext = pathExtension.lowercased()
            let name = fullFilename.lowercased()
            switch ext {
            case "zip":
                self = .zip
            case "tar":
                self = .tar
            case "gz":
                if name.hasSuffix(".tar.gz") { self = .tarGz }
                else { return nil }
            case "tgz":
                self = .tarGz
            case "bz2":
                if name.hasSuffix(".tar.bz2") { self = .tarBz2 }
                else { return nil }
            case "xz":
                if name.hasSuffix(".tar.xz") { self = .tarXz }
                else { return nil }
            default:
                return nil
            }
        }
    }

    // MARK: - Extraction

    /// Extract an archive to the given destination directory.
    func extract(archive url: URL, to destination: URL) throws {
        let format = ArchiveFormat(
            pathExtension: url.pathExtension,
            fullFilename: url.lastPathComponent
        )

        guard let format else {
            throw ArchiveError.unsupportedFormat(url.pathExtension)
        }

        switch format {
        case .zip:
            try extractZip(url, to: destination)
        case .tar, .tarGz, .tarBz2, .tarXz:
            try extractTar(url, to: destination)
        }
    }

    // MARK: - ZIP Extraction (ZIPFoundation)

    private func extractZip(_ url: URL, to destination: URL) throws {
        let archive = try Archive(url: url, accessMode: .read)

        var totalSize: UInt64 = 0
        var count = 0
        for entry in archive {
            count += 1
            guard count <= maximumEntries else { throw ArchiveError.archiveTooLarge }
            try Task.checkCancellation()
            guard entry.type != .symlink else {
                throw ArchiveError.unsafeEntry(entry.path)
            }
            do {
                _ = try ArchivePathValidator.safeDestination(
                    for: entry.path,
                    in: destination,
                    isDirectory: entry.type == .directory
                )
            } catch {
                throw ArchiveError.unsafeEntry(entry.path)
            }
            let (newTotal, overflow) = totalSize.addingReportingOverflow(
                UInt64(entry.uncompressedSize)
            )
            guard !overflow, newTotal <= maximumExpandedBytes else {
                throw ArchiveError.archiveTooLarge
            }
            totalSize = newTotal
        }

        var written: UInt64 = 0
        for entry in archive {
            try Task.checkCancellation()
            let target = try ArchivePathValidator.safeDestination(
                for: entry.path, in: destination, isDirectory: entry.type == .directory
            )
            if entry.type == .directory {
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let fd = Darwin.open(target.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw ArchiveError.unsafeEntry(entry.path) }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            do {
                _ = try archive.extract(entry) { data in
                    try Task.checkCancellation()
                    let (total, overflow) = written.addingReportingOverflow(UInt64(data.count))
                    guard !overflow, total <= maximumExpandedBytes else { throw ArchiveError.archiveTooLarge }
                    written = total
                    try handle.write(contentsOf: data)
                }
                try handle.close()
            } catch {
                try? handle.close()
                try? FileManager.default.removeItem(at: target)
                throw error
            }
        }
    }

    // MARK: - Tar Extraction (macOS libarchive)

    private func extractTar(_ url: URL, to destination: URL) throws {
        try TarArchiveReader(url: url).extract(
            to: destination, maximumBytes: maximumExpandedBytes, maximumEntries: maximumEntries
        )
    }

    // MARK: - ZIP Creation

    /// Create a ZIP archive at the given destination containing the specified entries.
    /// Each entry is a `(source: URL, archivePath: String)` pair where `archivePath`
    /// is the relative path within the archive (e.g., "Mods/SomeMod.pak").
    func createZip(
        at destination: URL,
        entries: [(source: URL, archivePath: String)],
        progress: ((Double) -> Void)? = nil
    ) throws {
        let archive: Archive
        do {
            archive = try Archive(url: destination, accessMode: .create)
        } catch {
            throw ArchiveError.zipCreationFailed("Could not create archive at \(destination.path): \(error.localizedDescription)")
        }

        let total = Double(entries.count)
        for (index, entry) in entries.enumerated() {
            try archive.addEntry(
                with: entry.archivePath,
                fileURL: entry.source
            )
            progress?(Double(index + 1) / total)
        }
    }
}
