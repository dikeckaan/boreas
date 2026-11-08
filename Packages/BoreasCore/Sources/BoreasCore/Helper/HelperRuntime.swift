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
    /// While the set of unverified fans stays the same, its fault is logged at most this often.
    public static let unverifiedLogIntervalSeconds: TimeInterval = 60
    /// What `apply` answers when the helper runs without its sensor catalog.
    public static let catalogUnavailableMessage =
        "The helper could not load its sensor catalog; fan control is disabled and every fan stays automatic."

    public static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private let fanController: FanController
    private let sensors: SensorReader
    private let now: () -> Date
    private let helperVersion: String
    private let startTime: Date
    /// False when the sensor catalog failed to load: the helper then refuses every configuration
    /// (all fans stay auto), because safety sensors and names cannot be trusted.
    private let catalogAvailable: Bool

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
    /// Unverified set and time of the last fault logged for it (rate limit).
    private var loggedUnverified: Set<Int> = []
    private var loggedUnverifiedAt: Date?
    /// Number of unverified-fan faults logged; for tests.
    private(set) var unverifiedFaultLogCount = 0

    public init(fans: FanController, sensors: SensorReader, now: @escaping () -> Date,
                helperVersion: String = HelperRuntime.bundleVersion, catalogAvailable: Bool = true) {
        self.fanController = fans
        self.sensors = sensors
        self.now = now
        self.helperVersion = helperVersion
        self.catalogAvailable = catalogAvailable
        self.startTime = now()
        // A previous helper instance may have died with a fan in manual mode.
        noteUnverified(fans.setAllAuto())
    }

    // MARK: - Client events

    /// Stores the configuration and, unless asleep, applies it right away. Returns an error message
    /// instead when the helper refuses manual control (no sensor catalog); fans then stay auto.
    @discardableResult
    public func apply(_ c: HelperConfiguration) -> String? {
        guard catalogAvailable else {
            log.error("configuration refused: sensor catalog unavailable")
            return Self.catalogUnavailableMessage
        }
        configuration = c
        control()
        return nil
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
                              ceilingTripped: engine.ceiling.tripped,
                              ceilingBlind: configuration != nil && engine.ceiling.blind,
                              catalogUnavailable: !catalogAvailable, helperVersion: helperVersion,
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

    /// Logs the unverified set when it changed, or at most once per `unverifiedLogIntervalSeconds`
    /// while it stays the same (it is retried every tick).
    private func logUnverified() {
        let t = now()
        defer { if unverifiedFans.isEmpty { loggedUnverified = [] } }
        guard !unverifiedFans.isEmpty else { return }
        if unverifiedFans == loggedUnverified, let last = loggedUnverifiedAt {
            let elapsed = t.timeIntervalSince(last)
            if elapsed >= 0 && elapsed < Self.unverifiedLogIntervalSeconds { return }
        }
        loggedUnverified = unverifiedFans
        loggedUnverifiedAt = t
        unverifiedFaultLogCount += 1
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

    private func markUnverified(_ fan: Int) {
        unverifiedFans.insert(fan)
        logUnverified()
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
        // A fan whose real mode disagrees with the cached command (reset by something else, or a
        // write that did not stick) has unknown state: forget the cache so it is rewritten. Unverified
        // fans are skipped: their reset is already retried every tick by `retryUnverified`.
        for fan in fans where !unverifiedFans.contains(fan.index) {
            guard let cached = applied[fan.index] else { continue }
            let cachedManual: Bool
            if case .manual = cached { cachedManual = true } else { cachedManual = false }
            if cachedManual != fan.isManual { applied[fan.index] = nil }
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
                case .auto:
                    try fanController.setAuto(fan: fan)
                    // Verified only once the mode reads back as auto.
                    if fanController.isManual(fan: fan) { markUnverified(fan) } else { unverifiedFans.remove(fan) }
                case .manual(let rpm):
                    try fanController.setManual(fan: fan, rpm: rpm)
                    unverifiedFans.remove(fan)
                }
                applied[fan] = command
                backoffUntil[fan] = nil
            } catch {
                log.fault("fan \(fan, privacy: .public) write failed: \(String(describing: error), privacy: .public)")
                if (try? fanController.setAuto(fan: fan)) == nil || fanController.isManual(fan: fan) {
                    markUnverified(fan)
                }
                applied[fan] = .auto
                backoffUntil[fan] = t.addingTimeInterval(Self.writeFailureBackoffSeconds)
            }
        }
    }
}
