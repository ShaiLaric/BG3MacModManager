import Foundation
import ZIPFoundation

/// Handles extraction of various archive formats (ZIP, tar variants) and ZIP creation.
final class ArchiveService {

    enum ArchiveError: Error, LocalizedError {
        case unsupportedFormat(String)
        case extractionFailed(String)
        case tarNotFound
        case zipCreationFailed(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext):
                return "Unsupported archive format: \(ext)"
            case .extractionFailed(let msg):
                return "Archive extraction failed: \(msg)"
            case .tarNotFound:
                return "/usr/bin/tar not found"
            case .zipCreationFailed(let msg):
                return "Failed to create ZIP archive: \(msg)"
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
        try FileManager.default.unzipItem(at: url, to: destination)
    }

    // MARK: - Tar Extraction (/usr/bin/tar)

    private func extractTar(_ url: URL, to destination: URL) throws {
        let tarPath = "/usr/bin/tar"
        guard FileManager.default.fileExists(atPath: tarPath) else {
            throw ArchiveError.tarNotFound
        }

        // macOS tar auto-detects compression format
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tarPath)
        process.arguments = ["xf", url.path, "-C", destination.path]

        let pipe = Pipe()
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
            let errorMsg = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ArchiveError.extractionFailed(errorMsg)
        }
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
        guard let archive = Archive(url: destination, accessMode: .create) else {
            throw ArchiveError.zipCreationFailed("Could not create archive at \(destination.path)")
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
