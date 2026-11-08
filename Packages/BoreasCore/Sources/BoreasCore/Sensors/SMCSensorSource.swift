import Foundation

/// Reads every SMC `T*` key of type `flt ` or `sp78`. The key list is discovered once and cached.
public final class SMCSensorSource: SensorSource, @unchecked Sendable {
    private let smc: SMCClient
    private let lock = NSLock()
    private var keys: [FourCC]?

    public init(smc: SMCClient) { self.smc = smc }

    private func sensorKeys() -> [FourCC] {
        lock.withLock {
            if let keys { return keys }
            var found: [FourCC] = []
            for k in (try? smc.allKeys()) ?? [] where k.description.hasPrefix("T") {
                guard let v = try? smc.read(k), v.type == "flt " || v.type == "sp78" else { continue }
                found.append(k)
            }
            keys = found
            return found
        }
    }

    public func read() -> [(id: SensorID, rawName: String, celsius: Double)] {
        sensorKeys().compactMap { k in
            guard let v = (try? smc.read(k))?.doubleValue else { return nil }
            return (SensorID("smc:\(k)"), k.description, v)
        }
    }
}
