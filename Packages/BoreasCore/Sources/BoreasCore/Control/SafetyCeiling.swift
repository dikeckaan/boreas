import Foundation

/// Independent over-temperature guard: trips when the 5 s average of the hottest
/// safety sensor exceeds `tripC`, releases when it falls below `releaseC`.
///
/// It also fails safe when it cannot see: with no valid safety input (the safety set, or the
/// cpu/gpu fallback) for more than `windowSeconds`, `blind` is set and the engine hands every
/// controlled fan back to Apple until input returns.
public struct SafetyCeiling: Sendable {
    public static let tripC = 100.0
    public static let releaseC = 90.0
    public static let windowSeconds = 5.0

    /// Safety sensors known without the catalog, so a missing or mismatched catalog cannot leave
    /// the ceiling without input. A trailing `*` matches any rest of the id; otherwise exact.
    public static let compiledSafetyPatterns = ["smc:TCMb", "smc:Tp*", "smc:Te*", "smc:Tg*"]

    private var samples: [(t: Date, c: Double)] = []
    public private(set) var tripped = false
    /// No valid safety input for more than `windowSeconds`.
    public private(set) var blind = false
    /// Last valid input, and when watching (re)started; blindness counts from the later of the two.
    private var lastInputAt: Date?
    private var watchingSince: Date?

    public init() {}

    /// A reading the ceiling watches: flagged by the catalog or matching the compiled-in set,
    /// and neither a hotspot nor suspect.
    public static func isSafety(_ r: SensorReading) -> Bool {
        guard !r.hotspot, !r.suspect else { return false }
        return r.safety || matchesCompiledPattern(r.id)
    }

    static func matchesCompiledPattern(_ id: SensorID) -> Bool {
        compiledSafetyPatterns.contains { p in
            p.hasSuffix("*") ? id.rawValue.hasPrefix(p.dropLast()) : id.rawValue == p
        }
    }

    /// Feeds this step's readings; returns whether the ceiling is tripped.
    @discardableResult
    public mutating func update(readings: [SensorReading], now: Date) -> Bool {
        // A backward clock jump invalidates the window and restarts the blindness watch.
        if let newest = samples.last?.t, now < newest { samples.removeAll() }
        if let latest = lastInputAt ?? watchingSince, now < latest {
            watchingSince = now
            lastInputAt = nil
        }
        let since = watchingSince ?? now
        watchingSince = since
        if let input = Self.input(from: readings) {
            samples.append((now, input))
            lastInputAt = now
        }
        samples.removeAll {
            let age = now.timeIntervalSince($0.t)
            return !(age >= 0 && age < Self.windowSeconds)
        }
        blind = now.timeIntervalSince(lastInputAt ?? since) > Self.windowSeconds
        guard !samples.isEmpty else { return tripped }
        let avg = samples.reduce(0) { $0 + $1.c } / Double(samples.count)
        if avg > Self.tripC {
            tripped = true
        } else if avg < Self.releaseC {
            tripped = false
        }
        return tripped
    }

    private static func input(from readings: [SensorReading]) -> Double? {
        let valid = readings.filter { SensorReader.isValid($0.celsius) }
        if let m = valid.filter(isSafety).map(\.celsius).max() { return m }
        return valid.filter { !$0.suspect && ($0.group == .cpu || $0.group == .gpu) }
            .map(\.celsius).max()
    }
}
