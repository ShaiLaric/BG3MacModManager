// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Encodes and decodes BG3's Version64 format.
///
/// BG3 stores version numbers as a single Int64 value with bit-packed components:
/// - Bits 55-63: Major (9 bits, max 511)
/// - Bits 47-54: Minor (8 bits, max 255)
/// - Bits 31-46: Revision (16 bits, max 65535)
/// - Bits 0-30:  Build (31 bits)
struct Version64: Codable, Equatable, Comparable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let revision: Int
    let build: Int

    /// The raw Int64 value as used by BG3.
    var rawValue: Int64 {
        var value: Int64 = 0
        value |= Int64(major) << 55
        value |= Int64(minor) << 47
        value |= Int64(revision) << 31
        value |= Int64(build)
        return value
    }

    /// Human-readable version string, e.g. "1.0.0.0".
    var description: String {
        "\(major).\(minor).\(revision).\(build)"
    }

    init(major: Int = 0, minor: Int = 0, revision: Int = 0, build: Int = 0) {
        self.major = major
        self.minor = minor
        self.revision = revision
        self.build = build
    }

    /// Decode from a BG3 Version64 raw Int64 value.
    init(rawValue: Int64) {
        self.major    = Int((rawValue >> 55) & 0x1FF)    // 9 bits
        self.minor    = Int((rawValue >> 47) & 0xFF)     // 8 bits
        self.revision = Int((rawValue >> 31) & 0xFFFF)   // 16 bits
        self.build    = Int(rawValue & 0x7FFFFFFF)       // 31 bits
    }

    /// Parse from a raw string representation of the Int64 value.
    init?(rawString: String) {
        guard let value = Int64(rawString) else { return nil }
        self.init(rawValue: value)
    }

    /// Parse from a dotted version string like "1.0.0.0".
    init?(versionString: String) {
        let parts = versionString.split(separator: ".").compactMap { Int($0) }
        guard parts.count >= 1 else { return nil }
        self.major    = parts[0]
        self.minor    = parts.count > 1 ? parts[1] : 0
        self.revision = parts.count > 2 ? parts[2] : 0
        self.build    = parts.count > 3 ? parts[3] : 0
    }

    static func < (lhs: Version64, rhs: Version64) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
