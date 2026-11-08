import Foundation

/// Per-sensor display preferences. They only affect what the app shows; rules keep working on
/// hidden sensors.
public struct SensorPrefs: Codable, Equatable, Sendable {
    public var starred: Set<SensorID>
    public var renamed: [SensorID: String]
    public var hidden: Set<SensorID>

    public init(starred: Set<SensorID> = [], renamed: [SensorID: String] = [:], hidden: Set<SensorID> = []) {
        self.starred = starred
        self.renamed = renamed
        self.hidden = hidden
    }

    private enum CodingKeys: String, CodingKey { case starred, renamed, hidden }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        starred = try c.decodeIfPresent(Set<SensorID>.self, forKey: .starred) ?? []
        renamed = try c.decodeIfPresent([SensorID: String].self, forKey: .renamed) ?? [:]
        hidden = try c.decodeIfPresent(Set<SensorID>.self, forKey: .hidden) ?? []
    }

    /// The user's name for the sensor, else the catalog name.
    public func displayName(_ r: SensorReading) -> String {
        renamed[r.id] ?? r.name
    }

    /// The `count` hottest sensors, hidden and `suspect` ones excluded, hottest first.
    public func hottest(_ readings: [SensorReading], count: Int) -> [SensorReading] {
        Array(readings.filter { !hidden.contains($0.id) && !$0.suspect && SensorReader.isValid($0.celsius) }
            .sorted { $0.celsius > $1.celsius }
            .prefix(Swift.max(0, count)))
    }
}

public enum MenuBarDisplay: String, Codable, CaseIterable, Sendable {
    case iconOnly, temperature, fanSpeed, both
}

public enum TemperatureUnit: String, Codable, Sendable {
    case celsius, fahrenheit
}

/// Everything the app persists. Decoding tolerates missing keys (each takes its default) so a
/// file written by an older version keeps the user's settings.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Built-ins included.
    public var profiles: [Profile]
    public var activeProfileID: UUID
    /// Explicit per-fan modes. A fan missing here counts as `.auto`.
    public var fanModes: [Int: FanMode]
    public var sensorPrefs: SensorPrefs
    public var menuBarDisplay: MenuBarDisplay = .temperature
    public var menuBarSensor: SensorSourceRef = .group(.cpu)
    public var unit: TemperatureUnit = .celsius
    /// Seconds between samples.
    public var sampleInterval: Double = 1
    public var historyCollapsed = false

    public init(profiles: [Profile] = BuiltInProfiles.all(),
                activeProfileID: UUID = BuiltInProfiles.automaticID,
                fanModes: [Int: FanMode] = [:],
                sensorPrefs: SensorPrefs = SensorPrefs(),
                menuBarDisplay: MenuBarDisplay = .temperature,
                menuBarSensor: SensorSourceRef = .group(.cpu),
                unit: TemperatureUnit = .celsius,
                sampleInterval: Double = 1,
                historyCollapsed: Bool = false) {
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        self.fanModes = fanModes
        self.sensorPrefs = sensorPrefs
        self.menuBarDisplay = menuBarDisplay
        self.menuBarSensor = menuBarSensor
        self.unit = unit
        self.sampleInterval = sampleInterval
        self.historyCollapsed = historyCollapsed
    }

    public static var defaults: AppSettings { AppSettings() }

    private enum CodingKeys: String, CodingKey {
        case profiles, activeProfileID, fanModes, sensorPrefs, menuBarDisplay, menuBarSensor, unit,
             sampleInterval, historyCollapsed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings.defaults
        profiles = try c.decodeIfPresent([Profile].self, forKey: .profiles) ?? d.profiles
        activeProfileID = try c.decodeIfPresent(UUID.self, forKey: .activeProfileID) ?? d.activeProfileID
        fanModes = try c.decodeIfPresent([Int: FanMode].self, forKey: .fanModes) ?? d.fanModes
        sensorPrefs = try c.decodeIfPresent(SensorPrefs.self, forKey: .sensorPrefs) ?? d.sensorPrefs
        menuBarDisplay = try c.decodeIfPresent(MenuBarDisplay.self, forKey: .menuBarDisplay) ?? d.menuBarDisplay
        menuBarSensor = try c.decodeIfPresent(SensorSourceRef.self, forKey: .menuBarSensor) ?? d.menuBarSensor
        unit = try c.decodeIfPresent(TemperatureUnit.self, forKey: .unit) ?? d.unit
        sampleInterval = try c.decodeIfPresent(Double.self, forKey: .sampleInterval) ?? d.sampleInterval
        historyCollapsed = try c.decodeIfPresent(Bool.self, forKey: .historyCollapsed) ?? d.historyCollapsed
    }

    // MARK: - Profiles

    public var activeProfile: Profile? {
        profiles.first { $0.id == activeProfileID }
    }

    /// What the helper gets: the explicit modes, plus the active profile (nil when it is Automatic).
    public var helperConfiguration: HelperConfiguration {
        let profile = activeProfileID == BuiltInProfiles.automaticID ? nil : activeProfile
        return HelperConfiguration(fanModes: fanModes, profile: profile)
    }

    /// Spec §5.3. Automatic puts every fan on `.auto`. Any other profile moves `.auto` fans
    /// (missing ones included) to `.profile` and leaves `.fixed` fans alone. `fans` are the fan
    /// indices currently known; fans already in `fanModes` are covered too. Unknown ids are ignored.
    public mutating func selectProfile(_ id: UUID, fans: [Int]) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
        let all = Set(fans).union(fanModes.keys)
        for fan in all {
            if id == BuiltInProfiles.automaticID {
                fanModes[fan] = .auto
            } else if (fanModes[fan] ?? .auto) == .auto {
                fanModes[fan] = .profile
            }
        }
    }

    public mutating func setFanMode(_ fan: Int, _ mode: FanMode) {
        fanModes[fan] = mode
    }

    /// Inserts or replaces by id. The Automatic profile is not editable.
    public mutating func saveProfile(_ p: Profile) {
        guard p.id != BuiltInProfiles.automaticID else { return }
        if let i = profiles.firstIndex(where: { $0.id == p.id }) {
            profiles[i] = p
        } else {
            profiles.append(p)
        }
    }

    /// Built-ins cannot be deleted. Deleting the active profile makes Automatic active and moves
    /// `.profile` fans to `.auto`; `.fixed` fans keep their speed.
    public mutating func deleteProfile(_ id: UUID) {
        guard let i = profiles.firstIndex(where: { $0.id == id }), profiles[i].builtIn == nil,
              !BuiltInProfiles.all().contains(where: { $0.id == id }) else { return }
        profiles.remove(at: i)
        if activeProfileID == id {
            activeProfileID = BuiltInProfiles.automaticID
            for (fan, mode) in fanModes where mode == .profile { fanModes[fan] = .auto }
        }
    }

    /// Puts back missing built-in profiles (in their usual order, ahead of user profiles) and
    /// falls back to Automatic if the active profile no longer exists.
    public mutating func normalize() {
        for (i, builtIn) in BuiltInProfiles.all().enumerated() where !profiles.contains(where: { $0.id == builtIn.id }) {
            profiles.insert(builtIn, at: Swift.min(i, profiles.count))
        }
        if !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = BuiltInProfiles.automaticID
        }
    }
}
