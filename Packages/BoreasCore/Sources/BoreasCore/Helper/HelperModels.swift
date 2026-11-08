import Foundation

/// What the user wants for one fan.
public enum FanMode: Codable, Equatable, Sendable {
    case auto
    case fixed(rpm: Double)
    case profile
}

/// What the engine tells the helper to do with one fan.
public enum FanCommand: Equatable, Sendable {
    case auto
    case manual(rpm: Double)
}

/// What the app sends the helper: per-fan modes plus the profile used by `.profile` fans.
public struct HelperConfiguration: Codable, Equatable, Sendable {
    public var fanModes: [Int: FanMode]
    public var profile: Profile?

    public init(fanModes: [Int: FanMode], profile: Profile?) {
        self.fanModes = fanModes
        self.profile = profile
    }
}

/// What the helper reports back to the app.
public struct HelperSnapshot: Codable, Equatable, Sendable {
    public var fans: [FanInfo]
    public var sensors: [SensorReading]
    /// Last command successfully applied per fan: `"auto"` or `"manual:<rpm>"` (whole rpm).
    public var commands: [Int: String]
    public var ceilingTripped: Bool
    public var helperVersion: String

    public init(fans: [FanInfo], sensors: [SensorReading], commands: [Int: String],
                ceilingTripped: Bool, helperVersion: String) {
        self.fans = fans
        self.sensors = sensors
        self.commands = commands
        self.ceilingTripped = ceilingTripped
        self.helperVersion = helperVersion
    }
}
