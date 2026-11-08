import Foundation
@testable import BoreasCore

let t0 = Date(timeIntervalSince1970: 1_800_000_000)
let testFan = FanInfo(index: 0, actual: 1000, min: 1000, max: 4900, target: 1000, isManual: false)

func reading(_ id: String, _ group: SensorGroup, _ c: Double, safety: Bool = false, suspect: Bool = false) -> SensorReading {
    SensorReading(id: SensorID(id), rawName: id, name: id, group: group, celsius: c,
                  featured: false, safety: safety, suspect: suspect)
}

func cpuGpu(cpu: Double?, gpu: Double? = nil) -> [SensorReading] {
    var r: [SensorReading] = []
    if let cpu { r.append(reading("hid:cpu", .cpu, cpu)) }
    if let gpu { r.append(reading("hid:gpu", .gpu, gpu)) }
    return r
}

let engineSilentCurve = Curve(points: [.init(celsius: 55, fraction: 0), .init(celsius: 95, fraction: 1)])
let cpuRuleID = UUID(uuidString: "00000000-0000-4000-8000-0000000000A1")!
let gpuRuleID = UUID(uuidString: "00000000-0000-4000-8000-0000000000A2")!

func profile(rules: [Rule]? = nil, smoothing: Bool = true, hyst: Double = 3, release: Bool = false) -> Profile {
    Profile(name: "T", builtIn: .silent,
            rules: rules ?? [Rule(id: cpuRuleID, source: .group(.cpu), curve: engineSilentCurve)],
            behavior: ProfileBehavior(smoothing: smoothing, hysteresisC: hyst, releaseToAppleBelowMin: release))
}

@discardableResult
func step(modes: [Int: FanMode]? = nil, profile p: Profile? = nil, readings: [SensorReading]? = nil,
          cpu: Double? = nil, gpu: Double? = nil, state: inout EngineState, t: Double = 0,
          fans: [FanInfo] = [testFan]) -> [Int: FanCommand] {
    ControlEngine.step(fans: fans, modes: modes ?? [0: p == nil ? .auto : .profile], profile: p,
                       readings: readings ?? cpuGpu(cpu: cpu, gpu: gpu), state: &state,
                       now: t0.addingTimeInterval(t))
}

func step(modes: [Int: FanMode]? = nil, profile p: Profile? = nil, readings: [SensorReading]? = nil,
          cpu: Double? = nil, gpu: Double? = nil) -> [Int: FanCommand] {
    var s = EngineState()
    return step(modes: modes, profile: p, readings: readings, cpu: cpu, gpu: gpu, state: &s)
}
