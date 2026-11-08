import Foundation
import os

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
        let catalog: SensorCatalog
        do { catalog = try SensorCatalog.bundled() } catch {
            Logger(subsystem: "com.kaandikec.boreas", category: "sensors")
                .fault("sensor catalog not found, using an empty one: \(String(describing: error), privacy: .public)")
            catalog = SensorCatalog(entries: [])
        }
        return SensorReader(sources: sources, catalog: catalog, language: language)
    }

    public func read() -> [SensorReading] {
        var readings: [SensorReading] = []
        var points: [String?] = []
        for source in sources {
            for r in source.read() where Self.isValid(r.celsius) {
                let m = catalog.match(r.id)
                readings.append(SensorReading(
                    id: r.id, rawName: r.rawName,
                    name: m?.name(language: language, rawName: r.rawName) ?? r.rawName,
                    group: m?.entry.group ?? .other, celsius: r.celsius,
                    featured: m?.entry.featured ?? false, safety: m?.entry.safety ?? false,
                    suspect: m?.entry.suspect ?? false,
                    hotspot: m?.entry.hotspot ?? false))
                points.append(m?.entry.point)
            }
        }
        // HID wins over other sources when both resolve to the same catalog `point` (cross-source only).
        let hidPoints = Set(readings.indices.filter { readings[$0].id.rawValue.hasPrefix("hid:") }.compactMap { points[$0] })
        return readings.indices.filter { i in
            guard let p = points[i] else { return true }
            return readings[i].id.rawValue.hasPrefix("hid:") || !hidPoints.contains(p)
        }.map { readings[$0] }
    }
}
