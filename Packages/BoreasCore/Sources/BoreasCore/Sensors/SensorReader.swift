import Foundation

public final class SensorReader: @unchecked Sendable {
    private let sources: [SensorSource]
    private let catalog: SensorCatalog
    private let language: String

    public init(sources: [SensorSource], catalog: SensorCatalog, language: String) {
        self.sources = sources
        self.catalog = catalog
        self.language = language
    }

    public static func isValid(_ c: Double) -> Bool { c.isFinite && c > 0 && c <= 150 }

    public static func live(language: String) -> SensorReader {
        var sources: [SensorSource] = []
        if let smc = try? IOKitSMCClient() { sources.append(SMCSensorSource(smc: smc)) }
        sources.append(HIDSensorSource())
        let catalog = (try? SensorCatalog.bundled()) ?? SensorCatalog(entries: [])
        return SensorReader(sources: sources, catalog: catalog, language: language)
    }

    public func read() -> [SensorReading] {
        var readings: [SensorReading] = []
        var matched = Set<Int>()  // indices of readings that resolved to a catalog entry
        for source in sources {
            for r in source.read() where Self.isValid(r.celsius) {
                let m = catalog.match(r.id)
                let reading = SensorReading(
                    id: r.id, rawName: r.rawName,
                    name: m?.name(language: language) ?? r.rawName,
                    group: m?.entry.group ?? .other, celsius: r.celsius,
                    featured: m?.entry.featured ?? false, safety: m?.entry.safety ?? false,
                    suspect: m?.entry.suspect ?? false)
                if m != nil { matched.insert(readings.count) }
                readings.append(reading)
            }
        }
        // HID wins over SMC when both resolve to the same catalog name (cross-source only).
        let hidNames = Set(readings.indices.filter { matched.contains($0) && readings[$0].id.rawValue.hasPrefix("hid:") }
            .map { readings[$0].name })
        return readings.enumerated().filter { i, r in
            !(matched.contains(i) && r.id.rawValue.hasPrefix("smc:") && hidNames.contains(r.name))
        }.map(\.element)
    }
}
