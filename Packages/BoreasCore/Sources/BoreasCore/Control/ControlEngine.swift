import Foundation

public struct EngineState: Sendable {
    /// Hysteresis memory, keyed by rule id.
    public var effectiveTemp: [UUID: Double]
    /// Last RPM commanded per fan index (smoothing baseline).
    public var lastRPM: [Int: Double]
    public var ceiling: SafetyCeiling
    public var lastTick: Date?

    public init() {
        effectiveTemp = [:]
        lastRPM = [:]
        ceiling = SafetyCeiling()
        lastTick = nil
    }
}

public enum ControlEngine {
    public static let rampUpRPMPerSecond = 600.0
    public static let rampDownRPMPerSecond = 300.0

    public static func step(fans: [FanInfo], modes: [Int: FanMode], profile: Profile?,
                            readings: [SensorReading], state: inout EngineState,
                            now: Date) -> [Int: FanCommand] {
        let tripped = state.ceiling.update(readings: readings, now: now)
        let dt = state.lastTick.map { now.timeIntervalSince($0) }
        defer { state.lastTick = now }

        // Rule temperatures are computed once per step (hysteresis is stateful).
        var ruleFractions: [(rule: Rule, fraction: Double)]?
        func fractions() -> [(rule: Rule, fraction: Double)] {
            if let ruleFractions { return ruleFractions }
            var out: [(Rule, Double)] = []
            if let profile, profile.builtIn != .automatic {
                for rule in profile.rules {
                    guard let t = temperature(for: rule.source, readings: readings) else { continue }
                    let h = profile.behavior.hysteresisC.isFinite ? Swift.max(0, profile.behavior.hysteresisC) : 3.0
                    var e = state.effectiveTemp[rule.id] ?? t
                    if t > e { e = t } else if t < e - h { e = t + h }
                    state.effectiveTemp[rule.id] = e
                    out.append((rule, rule.curve.fraction(at: e)))
                }
            }
            ruleFractions = out
            return out
        }

        var result: [Int: FanCommand] = [:]
        for fan in fans {
            let mode = modes[fan.index] ?? .auto
            guard fan.min.isFinite, fan.max.isFinite, fan.min <= fan.max, fan.max > 0 else {
                state.lastRPM[fan.index] = nil
                result[fan.index] = .auto
                continue
            }
            var command: FanCommand
            switch mode {
            case .auto:
                command = .auto
            case .fixed(let r):
                command = .manual(rpm: Swift.min(fan.max, Swift.max(fan.min, r)))
            case .profile:
                command = profileCommand(fan: fan, profile: profile, rules: fractions)
            }

            if tripped, mode != .auto {
                command = .manual(rpm: fan.max)
            } else if mode == .profile, case .manual(let target) = command,
                      profile?.behavior.smoothing == true,
                      let prev = state.lastRPM[fan.index], let dt, dt > 0 {
                let up = rampUpRPMPerSecond * dt, down = rampDownRPMPerSecond * dt
                let limited = Swift.min(prev + up, Swift.max(prev - down, target))
                command = .manual(rpm: Swift.min(fan.max, Swift.max(fan.min, limited)))
            }

            switch command {
            case .auto: state.lastRPM[fan.index] = nil
            case .manual(let rpm): state.lastRPM[fan.index] = rpm
            }
            result[fan.index] = command
        }
        return result
    }

    private static func profileCommand(fan: FanInfo, profile: Profile?,
                                       rules: () -> [(rule: Rule, fraction: Double)]) -> FanCommand {
        guard let profile, profile.builtIn != .automatic else { return .auto }
        let valid = rules()
        guard !valid.isEmpty else { return .auto }
        let rpm = valid.map { fan.min + $0.fraction * (fan.max - fan.min) }.max()!
        if profile.behavior.releaseToAppleBelowMin, rpm <= fan.min { return .auto }
        return .manual(rpm: rpm)
    }

    private static func temperature(for source: SensorSourceRef, readings: [SensorReading]) -> Double? {
        switch source {
        case .sensor(let id):
            return readings.first { $0.id == id && SensorReader.isValid($0.celsius) }?.celsius
        case .group(let g):
            return readings.filter { $0.group == g && !$0.suspect && SensorReader.isValid($0.celsius) }
                .map(\.celsius).max()
        }
    }
}
