import Foundation

/// One point of the history chart. Series keys: `cpu`, `gpu`, `fan0`, `fan1`, … and the raw ids
/// of starred sensors.
public struct HistorySample: Sendable, Equatable {
    public let date: Date
    public let values: [String: Double]

    public init(date: Date, values: [String: Double]) {
        self.date = date
        self.values = values
    }

    /// `cpu`/`gpu` are the group values (highest valid non-`suspect` member), `fanN` the actual
    /// rpm of fan N, starred sensors by raw id. Series with no value are left out.
    public init(date: Date, readings: [SensorReading], fans: [FanInfo], starred: Set<SensorID>) {
        var v: [String: Double] = [:]
        v["cpu"] = SensorSourceRef.group(.cpu).temperature(in: readings)
        v["gpu"] = SensorSourceRef.group(.gpu).temperature(in: readings)
        for fan in fans where fan.actual.isFinite { v["fan\(fan.index)"] = fan.actual }
        for id in starred { v[id.rawValue] = SensorSourceRef.sensor(id).temperature(in: readings) }
        self.init(date: date, values: v)
    }
}

/// Keeps the last `window` seconds (one hour) of samples, whatever the sampling interval.
/// `capacity` is only a safety cap (7200 = one hour at the fastest interval, 0.5 s); when it is
/// hit the oldest sample goes first.
public struct HistoryBuffer: Sendable {
    public let capacity: Int
    public let window: TimeInterval
    private var storage: [HistorySample] = []

    public init(capacity: Int = 7200, window: TimeInterval = 3600) {
        self.capacity = Swift.max(1, capacity)
        self.window = window
    }

    public mutating func append(_ s: HistorySample) {
        storage.append(s)
        let cutoff = s.date.addingTimeInterval(-window)
        let stale = storage.prefix { $0.date <= cutoff }.count
        let over = Swift.max(0, storage.count - capacity)
        let drop = Swift.max(stale, over)
        if drop > 0 { storage.removeFirst(drop) }
    }

    /// Samples with `date >= since`, oldest first.
    public func samples(since: Date) -> [HistorySample] {
        storage.filter { $0.date >= since }
    }
}
