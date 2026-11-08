import Foundation

public enum SensorGroup: String, Codable, CaseIterable, Sendable {
    case cpu, gpu, memory, storage, network, battery, power, other
}

/// `"smc:TC0P"` or `"hid:PMU tdie1"`.
/// Also `CodingKeyRepresentable`, so `[SensorID: T]` encodes as a JSON object keyed by the raw id.
public struct SensorID: Hashable, Codable, Sendable, RawRepresentable, CodingKeyRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }
}

public struct SensorReading: Codable, Sendable, Equatable {
    public let id: SensorID
    public let rawName: String
    public let name: String
    public let group: SensorGroup
    public let celsius: Double
    public let featured: Bool
    public let safety: Bool
    public let suspect: Bool

    public init(id: SensorID, rawName: String, name: String, group: SensorGroup, celsius: Double,
                featured: Bool, safety: Bool, suspect: Bool) {
        self.id = id; self.rawName = rawName; self.name = name; self.group = group
        self.celsius = celsius; self.featured = featured; self.safety = safety; self.suspect = suspect
    }
}

public protocol SensorSource {
    func read() -> [(id: SensorID, rawName: String, celsius: Double)]
}
