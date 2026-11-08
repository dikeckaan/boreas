import CIOHID
import CoreFoundation
import Foundation

/// Reads temperature services from the IOHID event system (usage page 0xff00, usage 5).
/// Returns an empty list when the system exposes none to this process.
public final class HIDSensorSource: SensorSource, @unchecked Sendable {
    public init() {}

    public func read() -> [(id: SensorID, rawName: String, celsius: Double)] {
        guard let client = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else { return [] }
        let matching: [String: Int] = [
            "PrimaryUsagePage": Int(kBoreasHIDPrimaryUsagePage),
            "PrimaryUsage": Int(kBoreasHIDPrimaryUsage),
        ]
        _ = IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
        guard let services = IOHIDEventSystemClientCopyServices(client) else { return [] }
        var out: [(id: SensorID, rawName: String, celsius: Double)] = []
        for i in 0..<CFArrayGetCount(services) {
            let service = unsafeBitCast(CFArrayGetValueAtIndex(services, i), to: IOHIDServiceClientRef.self)
            guard let prop = IOHIDServiceClientCopyProperty(service, "Product" as CFString),
                  let name = prop as? String else { continue }
            guard let event = IOHIDServiceClientCopyEvent(service, Int64(kBoreasIOHIDEventTypeTemperature), 0, 0) else { continue }
            let value = IOHIDEventGetFloatValue(event, Int32(kBoreasIOHIDEventFieldTemperatureLevel))
            out.append((SensorID("hid:\(name)"), name, value))
        }
        return out
    }
}
