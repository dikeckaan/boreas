import Foundation

/// What the user wants for one fan.
///
/// JSON: `{"kind":"auto"}`, `{"kind":"fixed","rpm":N}`, `{"kind":"profile"}`. Decoding also accepts
/// the shape the compiler used to synthesize (`{"auto":{}}`, `{"fixed":{"rpm":N}}`,
/// `{"profile":{}}`) so existing settings.json files keep loading.
public enum FanMode: Codable, Equatable, Sendable {
    case auto
    case fixed(rpm: Double)
    case profile

    private enum CodingKeys: String, CodingKey { case kind, rpm }
    private enum FixedKeys: String, CodingKey { case rpm }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let kind = try c.decodeIfPresent(String.self, forKey: .kind) {
            switch kind {
            case "auto": self = .auto
            case "profile": self = .profile
            case "fixed": self = .fixed(rpm: try c.decode(Double.self, forKey: .rpm))
            default:
                throw DecodingError.dataCorruptedError(forKey: .kind, in: c, debugDescription: "Unknown fan mode \(kind)")
            }
            return
        }
        // Old synthesized shape: a single key naming the case.
        let legacy = try decoder.container(keyedBy: LegacyKey.self)
        if legacy.contains(LegacyKey("fixed")) {
            let inner = try legacy.nestedContainer(keyedBy: FixedKeys.self, forKey: LegacyKey("fixed"))
            self = .fixed(rpm: try inner.decode(Double.self, forKey: .rpm))
        } else if legacy.contains(LegacyKey("auto")) {
            self = .auto
        } else if legacy.contains(LegacyKey("profile")) {
            self = .profile
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown fan mode"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .auto: try c.encode("auto", forKey: .kind)
        case .profile: try c.encode("profile", forKey: .kind)
        case .fixed(let rpm):
            try c.encode("fixed", forKey: .kind)
            try c.encode(rpm, forKey: .rpm)
        }
    }

    private struct LegacyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
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
public let boreasXPCFormatVersion = 2

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
