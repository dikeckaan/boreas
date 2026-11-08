import Foundation

public struct CatalogEntry: Codable, Sendable {
    public let match: String
    public let nameEN: String
    public let nameTR: String
    public let group: SensorGroup
    public let featured: Bool
    public let safety: Bool
    public let suspect: Bool
    /// Physical measurement point. A reading from another source sharing it with a HID
    /// reading is dropped (HID wins).
    public let point: String?

    public init(match: String, nameEN: String, nameTR: String, group: SensorGroup,
                featured: Bool, safety: Bool, suspect: Bool, point: String? = nil) {
        self.point = point
        self.match = match; self.nameEN = nameEN; self.nameTR = nameTR; self.group = group
        self.featured = featured; self.safety = safety; self.suspect = suspect
    }
}

public struct CatalogMatch: Sendable {
    public let entry: CatalogEntry
    /// Digits captured by `{n}`, if the pattern had one.
    public let number: String?

    /// Wildcard (`*`) entries without `{n}` get the raw name appended so rows stay distinguishable.
    public func name(language: String, rawName: String) -> String {
        var base = language.lowercased().hasPrefix("tr") ? entry.nameTR : entry.nameEN
        if let number { base = base.replacingOccurrences(of: "{n}", with: number) }
        if entry.match.contains("*") && !entry.match.contains("{n}") { base += " (\(rawName))" }
        return base
    }
}

/// Ordered list of patterns; the first matching entry wins. `*` matches any run of
/// characters, `{n}` captures one or more digits. Matched against the full SensorID string.
public struct SensorCatalog: @unchecked Sendable {
    public let entries: [CatalogEntry]
    private let compiled: [NSRegularExpression?]

    public init(entries: [CatalogEntry]) {
        self.entries = entries
        self.compiled = entries.map { Self.regex(for: $0.match) }
    }

    static func regex(for pattern: String) -> NSRegularExpression? {
        var out = "^"
        var rest = Substring(pattern)
        while let ch = rest.first {
            if rest.hasPrefix("{n}") {
                out += "(\\d+)"; rest = rest.dropFirst(3)
            } else if ch == "*" {
                out += ".*"; rest = rest.dropFirst()
            } else {
                out += NSRegularExpression.escapedPattern(for: String(ch)); rest = rest.dropFirst()
            }
        }
        out += "$"
        return try? NSRegularExpression(pattern: out, options: [.dotMatchesLineSeparators])
    }

    public func match(_ id: SensorID) -> CatalogMatch? {
        var s = id.rawValue
        // HID IDs carry a "#<discriminator>" suffix; catalog patterns match the Product part.
        if s.hasPrefix("hid:"), let hash = s.lastIndex(of: "#") { s = String(s[..<hash]) }
        let range = NSRange(s.startIndex..., in: s)
        for (entry, re) in zip(entries, compiled) {
            guard let re, let m = re.firstMatch(in: s, options: [], range: range) else { continue }
            var number: String?
            if m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) { number = String(s[r]) }
            return CatalogMatch(entry: entry, number: number)
        }
        return nil
    }

    public static func bundled() throws -> SensorCatalog {
        guard let url = Bundle.module.url(forResource: "sensor-catalog", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let entries = try JSONDecoder().decode([CatalogEntry].self, from: Data(contentsOf: url))
        return SensorCatalog(entries: entries)
    }
}
