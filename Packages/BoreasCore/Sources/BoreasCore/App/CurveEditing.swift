import Foundation

/// Pure curve edits for the profile editor. Every function returns a valid curve (sorted,
/// 20...110 °C, fraction 0...1, 2...8 points) or the input unchanged when the edit is not allowed.
public enum CurveEditing {
    public static let minCelsius = 20.0
    public static let maxCelsius = 110.0
    public static let minGap = 1.0
    public static let maxPoints = 8
    public static let minPoints = 2

    /// Moves point `index`. Temperature stays at least `minGap` from its neighbours and inside
    /// `minCelsius...maxCelsius`; fraction is clamped to 0...1. Out-of-range index: unchanged.
    public static func move(_ c: Curve, index: Int, to p: CurvePoint) -> Curve {
        var pts = c.points
        guard pts.indices.contains(index) else { return c }
        var lo = minCelsius, hi = maxCelsius
        if index > 0 { lo = Swift.max(lo, pts[index - 1].celsius + minGap) }
        if index < pts.count - 1 { hi = Swift.min(hi, pts[index + 1].celsius - minGap) }
        let t = p.celsius.isNaN ? pts[index].celsius : p.celsius
        let f = p.fraction.isNaN ? pts[index].fraction : p.fraction
        pts[index] = CurvePoint(celsius: Swift.min(Swift.max(t, lo), Swift.max(lo, hi)),
                                fraction: Swift.min(Swift.max(f, 0), 1))
        return Curve(points: pts)
    }

    /// Adds a point on the curve at `celsius`. Unchanged at 8 points, outside the temperature
    /// range, or within `minGap` of an existing point.
    public static func insert(_ c: Curve, at celsius: Double) -> Curve {
        guard c.points.count < maxPoints, celsius.isFinite,
              celsius >= minCelsius, celsius <= maxCelsius,
              !c.points.contains(where: { abs($0.celsius - celsius) < minGap }) else { return c }
        var pts = c.points
        pts.append(CurvePoint(celsius: celsius, fraction: c.fraction(at: celsius)))
        pts.sort { $0.celsius < $1.celsius }
        return Curve(points: pts)
    }

    /// Removes point `index`. Unchanged at 2 points or for an out-of-range index.
    public static func remove(_ c: Curve, index: Int) -> Curve {
        guard c.points.count > minPoints, c.points.indices.contains(index) else { return c }
        var pts = c.points
        pts.remove(at: index)
        return Curve(points: pts)
    }

    /// A user profile with new ids (profile and rules) and the same rules and behaviour.
    public static func duplicate(_ p: Profile, name: String) -> Profile {
        Profile(name: name, builtIn: nil,
                rules: p.rules.map { Rule(source: $0.source, curve: $0.curve) },
                behavior: p.behavior)
    }
}
