import Foundation
import os

private let log = Logger(subsystem: "com.kaandikec.boreas.helper", category: "runtime")

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
    /// After a write to a fan fails, manual commands for that fan wait this long before being retried.
    public static let writeFailureBackoffSeconds: TimeInterval = 30

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
    /// Fans a reset to auto could not be confirmed for. Treated as manual (no idle exit) and
    /// retried on every tick until the read-back says auto.
    private var unverifiedFans: Set<Int> = []
    /// Earliest time a manual command may be written again to a fan whose write failed.
    private var backoffUntil: [Int: Date] = [:]
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
        noteUnverified(fans.setAllAuto())
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

    /// Called once a second: retries unverified resets, handles the disconnect grace period,
    /// then runs one control pass.
    public func tick() {
        retryUnverified()
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
        clientCount == 0 && !hasManualFan && unverifiedFans.isEmpty
            && now().timeIntervalSince(lastDisconnect ?? startTime) >= Self.idleExitSeconds
    }

    public func snapshot() -> HelperSnapshot {
        let t = now()
        let fresh = lastReadingsAt.map { abs(t.timeIntervalSince($0)) < 2 } ?? false
        let readings = fresh ? lastReadings : sensors.read()
        var commands = applied.mapValues { c -> String in
            switch c {
            case .auto: return "auto"
            case .manual(let rpm): return "manual:\(Int(rpm.rounded()))"
            }
        }
        for fan in unverifiedFans { commands[fan] = "unverified" }
        return HelperSnapshot(fans: (try? fanController.fans()) ?? [], sensors: readings, commands: commands,
                              ceilingTripped: engine.ceiling.tripped, helperVersion: helperVersion,
                              formatVersion: boreasXPCFormatVersion)
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
        noteUnverified(fanController.setAllAuto(alsoFans: manualFans + unverifiedFans))
        applied = [:]
    }

    /// Records what `setAllAuto` could not confirm (it reports every such fan, so this replaces the set).
    private func noteUnverified(_ fans: [Int]) {
        unverifiedFans = Set(fans)
        logUnverified()
    }

    private func logUnverified() {
        guard !unverifiedFans.isEmpty else { return }
        let list = unverifiedFans.sorted().map(String.init).joined(separator: ", ")
        log.fault("fan(s) \(list, privacy: .public) could not be confirmed in automatic mode")
    }

    private func retryUnverified() {
        guard !unverifiedFans.isEmpty else { return }
        if hasManualFan {
            // Other fans are under control: setAllAuto would knock them back to auto, so retry
            // only the unverified fans and confirm by reading them back.
            for fan in unverifiedFans { try? fanController.setAuto(fan: fan) }
            let current = (try? fanController.fans()) ?? []
            unverifiedFans = unverifiedFans.filter { fan in current.first { $0.index == fan }?.isManual != false }
            logUnverified()
        } else {
            noteUnverified(fanController.setAllAuto(alsoFans: Array(unverifiedFans)))
        }
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

    /// Writes only commands that differ from what was last applied. If a write fails, only that
    /// fan goes back to auto and its manual commands wait `writeFailureBackoffSeconds`; other fans
    /// are left alone.
    private func write(_ commands: [Int: FanCommand]) {
        let t = now()
        for fan in commands.keys.sorted() {
            let command = commands[fan]!
            if applied[fan] == command { continue }
            if case .manual = command, let until = backoffUntil[fan], t < until { continue }
            do {
                switch command {
                case .auto: try fanController.setAuto(fan: fan)
                case .manual(let rpm): try fanController.setManual(fan: fan, rpm: rpm)
                }
                applied[fan] = command
                backoffUntil[fan] = nil
                unverifiedFans.remove(fan)
            } catch {
                log.fault("fan \(fan, privacy: .public) write failed: \(String(describing: error), privacy: .public)")
                do { try fanController.setAuto(fan: fan) } catch {
                    unverifiedFans.insert(fan)
                    logUnverified()
                }
                applied[fan] = .auto
                backoffUntil[fan] = t.addingTimeInterval(Self.writeFailureBackoffSeconds)
            }
        }
    }
}
