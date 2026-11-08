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

/// Version of the app-helper XPC payload format. Bump it when `HelperSnapshot` or
/// `HelperConfiguration` change in a way an older peer cannot read; the app re-registers a helper
/// whose snapshot reports a different value.
public let boreasXPCFormatVersion = 1

/// What the helper reports back to the app.
public struct HelperSnapshot: Codable, Equatable, Sendable {
    public var fans: [FanInfo]
    public var sensors: [SensorReading]
    /// Last command successfully applied per fan: `"auto"` or `"manual:<rpm>"` (whole rpm).
    public var commands: [Int: String]
    public var ceilingTripped: Bool
    public var helperVersion: String
    /// `boreasXPCFormatVersion` of the helper; 0 for a helper that predates the field.
    public var formatVersion: Int

    public init(fans: [FanInfo], sensors: [SensorReading], commands: [Int: String],
                ceilingTripped: Bool, helperVersion: String, formatVersion: Int = boreasXPCFormatVersion) {
        self.formatVersion = formatVersion
        self.fans = fans
        self.sensors = sensors
        self.commands = commands
        self.ceilingTripped = ceilingTripped
        self.helperVersion = helperVersion
    }

    private enum CodingKeys: String, CodingKey {
        case fans, sensors, commands, ceilingTripped, helperVersion, formatVersion
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fans = try c.decode([FanInfo].self, forKey: .fans)
        sensors = try c.decode([SensorReading].self, forKey: .sensors)
        commands = try c.decode([Int: String].self, forKey: .commands)
        ceilingTripped = try c.decode(Bool.self, forKey: .ceilingTripped)
        helperVersion = try c.decode(String.self, forKey: .helperVersion)
        formatVersion = try c.decodeIfPresent(Int.self, forKey: .formatVersion) ?? 0
    }
}
