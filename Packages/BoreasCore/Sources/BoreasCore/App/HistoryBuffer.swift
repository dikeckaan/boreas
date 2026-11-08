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

/// Fixed-capacity ring buffer, oldest sample dropped first. 3600 samples is one hour at 1 Hz.
public struct HistoryBuffer: Sendable {
    public let capacity: Int
    private var storage: [HistorySample] = []
    /// Index of the oldest sample once the buffer is full.
    private var head = 0

    public init(capacity: Int = 3600) {
        self.capacity = Swift.max(1, capacity)
        storage.reserveCapacity(Swift.min(self.capacity, 4096))
    }

    public mutating func append(_ s: HistorySample) {
        if storage.count < capacity {
            storage.append(s)
        } else {
            storage[head] = s
            head = (head + 1) % capacity
        }
    }

    /// Samples with `date >= since`, oldest first.
    public func samples(since: Date) -> [HistorySample] {
        let ordered = storage[head...] + storage[..<head]
        return ordered.filter { $0.date >= since }
    }
}
