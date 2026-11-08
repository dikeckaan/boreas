import Foundation

public enum Heat: Sendable, Equatable {
    case cool, warm, hot
}

/// What the main window's sensors column shows, and how.
public enum SensorPresentation {
    /// `warm` starts at the first value, `hot` at the second (inclusive).
    private static func thresholds(_ g: SensorGroup) -> (warm: Double, hot: Double) {
        switch g {
        case .cpu, .gpu: (70, 85)
        case .storage: (50, 65)
        case .battery: (40, 50)
        default: (60, 80)
        }
    }

    public static func heat(_ c: Double, group: SensorGroup) -> Heat {
        let t = thresholds(group)
        if c >= t.hot { return .hot }
        if c >= t.warm { return .warm }
        return .cool
    }

    /// Groups in declaration order, empty ones left out. Hidden sensors never appear. Collapsed
    /// (`showAll == false`): featured and starred sensors only, `suspect` ones not at all. Within a
    /// group, starred sensors come first; the rest keep their input order.
    public static func visible(_ r: [SensorReading], prefs: SensorPrefs,
                               showAll: Bool) -> [(SensorGroup, [SensorReading])] {
        let shown = r.filter { s in
            if prefs.hidden.contains(s.id) { return false }
            if showAll { return true }
            return !s.suspect && (s.featured || prefs.starred.contains(s.id))
        }
        return SensorGroup.allCases.compactMap { g in
            let members = shown.filter { $0.group == g }
            guard !members.isEmpty else { return nil }
            let starred = members.filter { prefs.starred.contains($0.id) }
            let rest = members.filter { !prefs.starred.contains($0.id) }
            return (g, starred + rest)
        }
    }

    public static func displayName(_ r: SensorReading, prefs: SensorPrefs) -> String {
        prefs.displayName(r)
    }

    /// Celsius value in the display unit.
    public static func value(_ c: Double, unit: TemperatureUnit) -> Double {
        unit == .fahrenheit ? c * 9 / 5 + 32 : c
    }

    /// Whole degrees with the unit letter: `62°C`, `212°F`.
    public static func format(_ c: Double, unit: TemperatureUnit) -> String {
        guard c.isFinite else { return "–" }
        return "\(Int(value(c, unit: unit).rounded()))°\(unit == .fahrenheit ? "F" : "C")"
    }

    /// At most `maxCount` evenly spaced elements, first and last kept (for drawing long histories).
    public static func thin<T>(_ a: [T], maxCount: Int) -> [T] {
        guard a.count > maxCount else { return a }
        guard maxCount > 1 else { return a.last.map { [$0] } ?? [] }
        let step = Double(a.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { a[Int((Double($0) * step).rounded())] }
    }
}
