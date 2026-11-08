import Foundation

public struct CurvePoint: Codable, Equatable, Sendable {
    public var celsius: Double
    public var fraction: Double
    public init(celsius: Double, fraction: Double) {
        self.celsius = celsius
        self.fraction = fraction
    }
}

/// Piecewise-linear temperature -> fan fraction (0...1 of the fan's [min, max] range).
public struct Curve: Codable, Equatable, Sendable {
    /// 2...8 points, sorted by celsius. Evaluation tolerates malformed curves.
    public var points: [CurvePoint]
    public init(points: [CurvePoint]) { self.points = points }

    public func fraction(at c: Double) -> Double {
        guard !c.isNaN else { return 0 }
        let pts = points.sorted { $0.celsius < $1.celsius }
        guard let first = pts.first, let last = pts.last else { return 0 }
        let result: Double
        if c <= first.celsius {
            result = first.fraction
        } else if c >= last.celsius {
            result = last.fraction
        } else {
            var r = last.fraction
            for i in 1..<pts.count where c <= pts[i].celsius {
                let a = pts[i - 1], b = pts[i]
                let span = b.celsius - a.celsius
                r = span > 0 ? a.fraction + (b.fraction - a.fraction) * (c - a.celsius) / span : b.fraction
                break
            }
            result = r
        }
        return result.isNaN ? 0 : min(1, max(0, result))
    }
}
