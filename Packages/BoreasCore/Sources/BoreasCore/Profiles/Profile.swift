import Foundation

/// Rule input: one sensor, or a group (the highest non-`suspect` member).
///
/// Persisted (and sent to the helper) as `{"kind":"sensor"|"group","value":"<sensor id or group>"}`.
public enum SensorSourceRef: Codable, Hashable, Sendable {
    case sensor(SensorID)
    case group(SensorGroup)

    private enum CodingKeys: String, CodingKey { case kind, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        let value = try c.decode(String.self, forKey: .value)
        switch kind {
        case "sensor":
            self = .sensor(SensorID(value))
        case "group":
            guard let g = SensorGroup(rawValue: value) else {
                throw DecodingError.dataCorruptedError(forKey: .value, in: c, debugDescription: "Unknown sensor group \(value)")
            }
            self = .group(g)
        default:
            throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown source kind \(kind)")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .sensor(let id):
            try c.encode("sensor", forKey: .kind)
            try c.encode(id.rawValue, forKey: .value)
        case .group(let g):
            try c.encode("group", forKey: .kind)
            try c.encode(g.rawValue, forKey: .value)
        }
    }

    /// The source's temperature: the sensor's value, or the highest valid non-`suspect` group
    /// member. nil when nothing valid matches.
    public func temperature(in readings: [SensorReading]) -> Double? {
        switch self {
        case .sensor(let id):
            return readings.first { $0.id == id && SensorReader.isValid($0.celsius) }?.celsius
        case .group(let g):
            return readings.filter { $0.group == g && !$0.suspect && SensorReader.isValid($0.celsius) }
                .map(\.celsius).max()
        }
    }
}

public struct Rule: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var source: SensorSourceRef
    public var curve: Curve
    public init(id: UUID = UUID(), source: SensorSourceRef, curve: Curve) {
        self.id = id
        self.source = source
        self.curve = curve
    }
}

public struct ProfileBehavior: Codable, Equatable, Sendable {
    public var smoothing = true
    public var hysteresisC = 3.0
    public var releaseToAppleBelowMin = false
    public init(smoothing: Bool = true, hysteresisC: Double = 3.0, releaseToAppleBelowMin: Bool = false) {
        self.smoothing = smoothing
        self.hysteresisC = hysteresisC
        self.releaseToAppleBelowMin = releaseToAppleBelowMin
    }

    private enum CodingKeys: String, CodingKey { case smoothing, hysteresisC, releaseToAppleBelowMin }

    /// Missing keys take their defaults, so adding a field later does not invalidate saved profiles.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ProfileBehavior()
        smoothing = try c.decodeIfPresent(Bool.self, forKey: .smoothing) ?? d.smoothing
        hysteresisC = try c.decodeIfPresent(Double.self, forKey: .hysteresisC) ?? d.hysteresisC
        releaseToAppleBelowMin = try c.decodeIfPresent(Bool.self, forKey: .releaseToAppleBelowMin) ?? d.releaseToAppleBelowMin
    }
}

public enum BuiltInKind: String, Codable, Sendable {
    case automatic, silent, performance
}

public struct Profile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var builtIn: BuiltInKind?
    public var rules: [Rule]
    public var behavior: ProfileBehavior
    public init(id: UUID = UUID(), name: String, builtIn: BuiltInKind? = nil,
                rules: [Rule] = [], behavior: ProfileBehavior = ProfileBehavior()) {
        self.id = id
        self.name = name
        self.builtIn = builtIn
        self.rules = rules
        self.behavior = behavior
    }
}

public enum BuiltInProfiles {
    public static let automaticID = UUID(uuidString: "B07EA500-0000-4000-8000-000000000001")!
    public static let silentID = UUID(uuidString: "B07EA500-0000-4000-8000-000000000002")!
    public static let performanceID = UUID(uuidString: "B07EA500-0000-4000-8000-000000000003")!

    public static func all() -> [Profile] {
        let silentCurve = Curve(points: [.init(celsius: 55, fraction: 0), .init(celsius: 95, fraction: 1)])
        let perfCurve = Curve(points: [.init(celsius: 40, fraction: 0.15),
                                       .init(celsius: 60, fraction: 0.5),
                                       .init(celsius: 80, fraction: 1.0)])
        return [
            Profile(id: automaticID, name: "Automatic", builtIn: .automatic),
            Profile(id: silentID, name: "Silent", builtIn: .silent, rules: [
                Rule(id: UUID(uuidString: "B07EA500-0000-4000-8000-000000000102")!, source: .group(.cpu), curve: silentCurve),
            ]),
            Profile(id: performanceID, name: "Performance", builtIn: .performance, rules: [
                Rule(id: UUID(uuidString: "B07EA500-0000-4000-8000-000000000103")!, source: .group(.cpu), curve: perfCurve),
                Rule(id: UUID(uuidString: "B07EA500-0000-4000-8000-000000000104")!, source: .group(.gpu), curve: perfCurve),
            ]),
        ]
    }
}
