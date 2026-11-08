import Foundation

/// Independent over-temperature guard: trips when the 5 s average of the hottest
/// safety sensor exceeds `tripC`, releases when it falls below `releaseC`.
public struct SafetyCeiling: Sendable {
    public static let tripC = 100.0
    public static let releaseC = 90.0
    public static let windowSeconds = 5.0

    private var samples: [(t: Date, c: Double)] = []
    public private(set) var tripped = false

    public init() {}

    /// Feeds this step's readings; returns whether the ceiling is tripped.
    @discardableResult
    public mutating func update(readings: [SensorReading], now: Date) -> Bool {
        // A backward clock jump invalidates the window.
        if let newest = samples.last?.t, now < newest { samples.removeAll() }
        if let input = Self.input(from: readings) {
            samples.append((now, input))
        }
        samples.removeAll {
            let age = now.timeIntervalSince($0.t)
            return !(age >= 0 && age < Self.windowSeconds)
        }
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
        if let m = valid.filter(\.safety).map(\.celsius).max() { return m }
        return valid.filter { !$0.suspect && ($0.group == .cpu || $0.group == .gpu) }
            .map(\.celsius).max()
    }
}
