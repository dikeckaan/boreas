import CIOHID
import CoreFoundation
import Foundation

/// Reads temperature services from the IOHID event system (usage page 0xff00, usage 5).
/// Returns an empty list when the system exposes none to this process.
///
/// IDs are `hid:<Product>#<LocationID as 8 hex digits>`. LocationID is stable per sensor across
/// reads and reboots (it is a four-character code on Apple Silicon). If a service lacks it, or two
/// services of one Product share it, an ordinal suffix (`-1`, `-2`, in service-list order) is added;
/// that ordinal is only as stable as the system's service ordering.
public final class HIDSensorSource: SensorSource, @unchecked Sendable {
    private struct Service {
        let ref: IOHIDServiceClientRef
        let id: SensorID
        let name: String
    }

    private let lock = NSLock()
    private let client: IOHIDEventSystemClientRef?
    private var serviceList: CFArray?      // keeps the borrowed service refs alive
    private var services: [Service] = []
    private var refreshedAt = Date.distantPast
    private let refreshInterval: TimeInterval = 60

    public init() {
        client = IOHIDEventSystemClientCreate(kCFAllocatorDefault)
        if let client {
            let matching: [String: Int] = [
                "PrimaryUsagePage": Int(kBoreasHIDPrimaryUsagePage),
                "PrimaryUsage": Int(kBoreasHIDPrimaryUsage),
            ]
            _ = IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)
        }
    }

    deinit {
        if let client { boreas_hid_release(UnsafeRawPointer(client)) }
    }

    private func refreshServicesIfNeeded() {
        guard let client else { return }
        if !services.isEmpty && Date().timeIntervalSince(refreshedAt) < refreshInterval { return }
        guard let list = IOHIDEventSystemClientCopyServices(client) else { return }
        var raw: [(IOHIDServiceClientRef, String, String)] = []
        for i in 0..<CFArrayGetCount(list) {
            let ref = unsafeBitCast(CFArrayGetValueAtIndex(list, i), to: IOHIDServiceClientRef.self)
            guard let name = IOHIDServiceClientCopyProperty(ref, "Product" as CFString) as? String else { continue }
            var disc = ""
            if let loc = IOHIDServiceClientCopyProperty(ref, "LocationID" as CFString) as? NSNumber {
                disc = String(format: "%08x", loc.uint32Value)
            }
            raw.append((ref, name, disc))
        }
        var seen: [String: Int] = [:]
        var built: [Service] = []
        for (ref, name, disc) in raw {
            let base = "hid:\(name)#\(disc)"
            let n = seen[base, default: 0]
            seen[base] = n + 1
            let id = (disc.isEmpty || n > 0) ? "\(base)-\(n + 1)" : base
            built.append(Service(ref: ref, id: SensorID(id), name: name))
        }
        serviceList = list
        services = built
        refreshedAt = Date()
    }

    public func read() -> [(id: SensorID, rawName: String, celsius: Double)] {
        lock.withLock {
            refreshServicesIfNeeded()
            var out: [(id: SensorID, rawName: String, celsius: Double)] = []
            for s in services {
                guard let event = IOHIDServiceClientCopyEvent(s.ref, Int64(kBoreasIOHIDEventTypeTemperature), 0, 0) else { continue }
                defer { boreas_hid_release(UnsafeRawPointer(event)) }
                out.append((s.id, s.name, IOHIDEventGetFloatValue(event, Int32(kBoreasIOHIDEventFieldTemperatureLevel))))
            }
            return out
        }
    }
}
