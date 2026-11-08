import Foundation

/// The helper's control loop, client bookkeeping and safety resets, kept free of XPC and
/// IOKit power APIs so it can be tested with a fake SMC and a fake clock.
///
/// **Threading:** not thread-safe. Every call (init included, XPC replies, timer ticks, power and
/// signal callbacks) must come from one serial queue; `Helper/main.swift` owns that queue.
/// `@unchecked Sendable` only so it can be captured by closures that hop onto that queue.
public final class HelperRuntime: @unchecked Sendable {
    /// After the last client disconnects, control continues this long before every fan goes back to auto.
    public static let disconnectGraceSeconds: TimeInterval = 3
    /// With no clients and no manual fan, the helper exits after this long.
    public static let idleExitSeconds: TimeInterval = 10

    public static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private let fanController: FanController
    private let sensors: SensorReader
    private let now: () -> Date
    private let helperVersion: String
    private let startTime: Date

    private var configuration: HelperConfiguration?
    private var engine = EngineState()
    /// Last command successfully written per fan. A fan missing here has unknown state and
    /// is rewritten on the next control pass.
    private var applied: [Int: FanCommand] = [:]
    public private(set) var clientCount = 0
    private var lastDisconnect: Date?
    private var asleep = false
    private var lastReadings: [SensorReading] = []
    private var lastReadingsAt: Date?

    public init(fans: FanController, sensors: SensorReader, now: @escaping () -> Date,
                helperVersion: String = HelperRuntime.bundleVersion) {
        self.fanController = fans
        self.sensors = sensors
        self.now = now
        self.helperVersion = helperVersion
        self.startTime = now()
        // A previous helper instance may have died with a fan in manual mode.
        fans.setAllAuto()
    }

    // MARK: - Client events

    /// Stores the configuration and, unless asleep, applies it right away.
    public func apply(_ c: HelperConfiguration) {
        configuration = c
        control()
    }

    /// Puts every fan back to auto and drops the configuration until the next `apply`.
    public func resetAllToAuto() {
        restoreAuto()
        dropConfiguration()
    }

    public func clientConnected() {
        clientCount += 1
    }

    public func clientDisconnected() {
        guard clientCount > 0 else { return }
        clientCount -= 1
        if clientCount == 0 { lastDisconnect = now() }
    }

    // MARK: - Loop and system events

    /// Called once a second: handles the disconnect grace period, then runs one control pass.
    public func tick() {
        if clientCount == 0, configuration != nil || hasManualFan {
            let elapsed = now().timeIntervalSince(lastDisconnect ?? startTime)
            // A negative interval means the clock went backwards; err on the side of auto.
            if elapsed < 0 || elapsed >= Self.disconnectGraceSeconds {
                resetAllToAuto()
                return
            }
        }
        control()
    }

    public func willSleep() {
        asleep = true
        restoreAuto()
    }

    public func didWake() {
        asleep = false
        if clientCount > 0, configuration != nil { control() }
    }

    /// SIGTERM, uninstall, update: every fan goes back to auto and nothing is re-applied.
    public func shutdown() {
        resetAllToAuto()
    }

    public var shouldExit: Bool {
        clientCount == 0 && !hasManualFan
            && now().timeIntervalSince(lastDisconnect ?? startTime) >= Self.idleExitSeconds
    }

    public func snapshot() -> HelperSnapshot {
        let t = now()
        let fresh = lastReadingsAt.map { abs(t.timeIntervalSince($0)) < 2 } ?? false
        let readings = fresh ? lastReadings : sensors.read()
        let commands = applied.mapValues { c -> String in
            switch c {
            case .auto: return "auto"
            case .manual(let rpm): return "manual:\(Int(rpm.rounded()))"
            }
        }
        return HelperSnapshot(fans: (try? fanController.fans()) ?? [], sensors: readings, commands: commands,
                              ceilingTripped: engine.ceiling.tripped, helperVersion: helperVersion)
    }

    // MARK: - Internals

    private var hasManualFan: Bool {
        applied.values.contains { if case .manual = $0 { return true } else { return false } }
    }

    private var manualFans: [Int] {
        applied.compactMap { fan, c in if case .manual = c { return fan } else { return nil } }.sorted()
    }

    /// Fans back to auto; tracking cleared so the next control pass rewrites every fan.
    private func restoreAuto() {
        fanController.setAllAuto(alsoFans: manualFans)
        applied = [:]
    }

    private func dropConfiguration() {
        configuration = nil
        engine = EngineState()
    }

    private func control() {
        guard let configuration, !asleep else { return }
        let t = now()
        let readings = sensors.read()
        lastReadings = readings
        lastReadingsAt = t
        let fans: [FanInfo]
        do { fans = try fanController.fans() } catch {
            // Without fan limits nothing can be computed safely.
            restoreAuto()
            return
        }
        let commands = ControlEngine.step(fans: fans, modes: configuration.fanModes, profile: configuration.profile,
                                          readings: readings, state: &engine, now: t)
            .mapValues { c -> FanCommand in
                if case .manual(let rpm) = c { return .manual(rpm: rpm.rounded()) }
                return c
            }
        write(commands)
    }

    /// Writes only commands that differ from what was last applied. A failed write sends that
    /// fan (and, through `setAllAuto`, every fan) back to auto; the other fans are then rewritten.
    private func write(_ commands: [Int: FanCommand]) {
        var failed: Set<Int> = []
        var retry = true
        while retry {
            retry = false
            for fan in commands.keys.sorted() where !failed.contains(fan) {
                let command = commands[fan]!
                if applied[fan] == command { continue }
                do {
                    switch command {
                    case .auto: try fanController.setAuto(fan: fan)
                    case .manual(let rpm): try fanController.setManual(fan: fan, rpm: rpm)
                    }
                    applied[fan] = command
                } catch {
                    failed.insert(fan)
                    fanController.setAllAuto(alsoFans: [fan])
                    // setAllAuto touched every fan: only the failed ones are known to be auto.
                    applied = Dictionary(uniqueKeysWithValues: failed.map { ($0, FanCommand.auto) })
                    retry = true
                    break
                }
            }
        }
    }
}
