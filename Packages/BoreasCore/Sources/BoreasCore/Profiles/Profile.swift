import Foundation

/// Rule input: one sensor, or a group (the highest non-`suspect` member).
public enum SensorSourceRef: Codable, Hashable, Sendable {
    case sensor(SensorID)
    case group(SensorGroup)
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
