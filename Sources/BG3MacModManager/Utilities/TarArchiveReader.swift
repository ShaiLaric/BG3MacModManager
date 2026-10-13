// SPDX-License-Identifier: GPL-3.0-or-later

import Darwin
import Foundation

/// Streams tar through macOS libarchive, enforcing limits on bytes actually written.
/// No subprocess pipes or unbounded listings are retained in memory.
final class TarArchiveReader {
    private typealias New = @convention(c) () -> OpaquePointer?
    private typealias Unary = @convention(c) (OpaquePointer?) -> Int32
    private typealias Open = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, Int) -> Int32
    private typealias Next = @convention(c) (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>?) -> Int32
    private typealias Text = @convention(c) (OpaquePointer?) -> UnsafePointer<CChar>?
    private typealias Number = @convention(c) (OpaquePointer?) -> Int64
    private typealias FileType = @convention(c) (OpaquePointer?) -> mode_t
    private typealias Read = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, Int) -> Int

    private let library: UnsafeMutableRawPointer
    private let reader: OpaquePointer
    private let free: Unary
    private let next: Next
    private let pathname: Text
    private let symlink: Text
    private let hardlink: Text
    private let errorString: Text
    private let size: Number
    private let fileType: FileType
    private let read: Read

    init(url: URL) throws {
        guard let library = dlopen("/usr/lib/libarchive.dylib", RTLD_NOW | RTLD_LOCAL) else {
            throw ArchiveService.ArchiveError.extractionFailed("macOS libarchive is unavailable")
        }
        func symbol<T>(_ name: String, as type: T.Type) throws -> T {
            guard let address = dlsym(library, name) else {
                throw ArchiveService.ArchiveError.extractionFailed("Missing libarchive function: " + name)
            }
            return unsafeBitCast(address, to: type)
        }
        var created: OpaquePointer?
        var release: Unary?
        do {
            let new = try symbol("archive_read_new", as: New.self)
            let free = try symbol("archive_read_free", as: Unary.self)
            release = free
            guard let reader = new() else {
                throw ArchiveService.ArchiveError.extractionFailed("Could not create archive reader")
            }
            created = reader
            let filters = try symbol("archive_read_support_filter_all", as: Unary.self)
            let format = try symbol("archive_read_support_format_tar", as: Unary.self)
            let open = try symbol("archive_read_open_filename", as: Open.self)
            _ = filters(reader)
            _ = format(reader)
            guard open(reader, url.path, 65_536) == 0 else {
                throw ArchiveService.ArchiveError.extractionFailed("Could not open tar archive")
            }
            self.library = library
            self.reader = reader
            self.free = free
            next = try symbol("archive_read_next_header", as: Next.self)
            pathname = try symbol("archive_entry_pathname", as: Text.self)
            symlink = try symbol("archive_entry_symlink", as: Text.self)
            hardlink = try symbol("archive_entry_hardlink", as: Text.self)
            errorString = try symbol("archive_error_string", as: Text.self)
            size = try symbol("archive_entry_size", as: Number.self)
            fileType = try symbol("archive_entry_filetype", as: FileType.self)
            read = try symbol("archive_read_data", as: Read.self)
        } catch {
            if let created, let release { _ = release(created) }
            dlclose(library)
            throw error
        }
    }

    deinit {
        _ = free(reader)
        dlclose(library)
    }

    func extract(to directory: URL, maximumBytes: UInt64, maximumEntries: Int) throws {
        var total: UInt64 = 0
        var declaredTotal: UInt64 = 0
        var count = 0
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            try Task.checkCancellation()
            var entry: OpaquePointer?
            let status = next(reader, &entry)
            if status == 1 { break } // ARCHIVE_EOF
            guard status == 0, let entry, let path = pathname(entry) else { throw failure() }
            count += 1
            guard count <= maximumEntries else { throw ArchiveService.ArchiveError.archiveTooLarge }
            let name = String(cString: path)
            let type = fileType(entry)
            guard symlink(entry) == nil, hardlink(entry) == nil,
                  type == 0o100000 || type == 0o040000 else {
                throw ArchiveService.ArchiveError.unsafeEntry(name)
            }
            let destination: URL
            do {
                destination = try ArchivePathValidator.safeDestination(
                    for: name, in: directory, isDirectory: type == 0o040000
                )
            } catch { throw ArchiveService.ArchiveError.unsafeEntry(name) }
            let length = size(entry)
            guard length >= 0 else { throw failure() }
            let (expanded, overflow) = declaredTotal.addingReportingOverflow(UInt64(length))
            guard !overflow, expanded <= maximumBytes else { throw ArchiveService.ArchiveError.archiveTooLarge }
            declaredTotal = expanded
            if type == 0o040000 {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                continue
            }
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            // Never write through an existing symlink or silently overwrite an archive duplicate.
            let fd = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
            guard fd >= 0 else { throw ArchiveService.ArchiveError.unsafeEntry(name) }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            do {
                while true {
                    try Task.checkCancellation()
                    let bytes = buffer.withUnsafeMutableBytes { read(reader, $0.baseAddress, $0.count) }
                    guard bytes >= 0 else { throw failure() }
                    if bytes == 0 { break }
                    let (expanded, overflow) = total.addingReportingOverflow(UInt64(bytes))
                    guard !overflow, expanded <= maximumBytes else { throw ArchiveService.ArchiveError.archiveTooLarge }
                    total = expanded
                    try handle.write(contentsOf: Data(buffer.prefix(bytes)))
                }
                try handle.close()
            } catch {
                try? handle.close()
                try? FileManager.default.removeItem(at: destination)
                throw error
            }
        }
    }

    private func failure() -> Error {
        ArchiveService.ArchiveError.extractionFailed(
            errorString(reader).map { String(cString: $0) } ?? "Unreadable tar archive"
        )
    }
}
