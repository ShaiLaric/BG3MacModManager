// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

enum ArchivePathValidator {
    enum PathError: Error, LocalizedError {
        case unsafe(String)

        var errorDescription: String? {
            switch self {
            case .unsafe(let path): return "Unsafe path in archive: \(path)"
            }
        }
    }

    static func safeDestination(
        for entryName: String,
        in destinationFolder: URL,
        isDirectory: Bool = false
    ) throws -> URL {
        var normalized = entryName.replacingOccurrences(of: "\\", with: "/")
        if isDirectory {
            while normalized.hasSuffix("/") { normalized.removeLast() }
        }

        guard !normalized.isEmpty,
              !normalized.hasPrefix("/"),
              !normalized.contains("\0") else {
            throw PathError.unsafe(entryName)
        }

        let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
              components.first?.contains(":") == false else {
            throw PathError.unsafe(entryName)
        }

        let root = destinationFolder.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = components.reduce(root) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: false)
        }.standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPrefix) else {
            throw PathError.unsafe(entryName)
        }
        return candidate
    }
}
