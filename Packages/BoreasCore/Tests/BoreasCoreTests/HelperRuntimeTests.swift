import Foundation
import Testing
@testable import BoreasCore

// MARK: - Fixtures

private final class FakeClock: @unchecked Sendable {
    var t = t0
    func now() -> Date { t }
    func advance(_ s: TimeInterval) { t = t.addingTimeInterval(s) }
}

private final class TempSource: SensorSource, @unchecked Sendable {
    var cpu = 50.0
    func read() -> [(id: SensorID, rawName: String, celsius: Double)] { [(SensorID("hid:cpu"), "cpu", cpu)] }
}

/// Wraps the fake SMC to count write attempts, including ones that fail.
private final class CountingSMC: SMCClient, @unchecked Sendable {
    let inner: FakeSMCClient
    private(set) var attempts: [FourCC: Int] = [:]
    /// Extra failure rule checked before the write reaches the fake.
    var reject: ((FourCC, [UInt8]) -> Bool)?
    /// Writes that report success but never reach the fake (an SMC that ignores the key).
    var ignore: ((FourCC, [UInt8]) -> Bool)?
    init(_ inner: FakeSMCClient) { self.inner = inner }
    func read(_ key: FourCC) throws -> SMCValue { try inner.read(key) }
    func write(_ key: FourCC, bytes: [UInt8]) throws {
        attempts[key, default: 0] += 1
        if reject?(key, bytes) == true { throw SMCError.ioFailure(-1) }
        if ignore?(key, bytes) == true { return }
        try inner.write(key, bytes: bytes)
    }
    func allKeys() throws -> [FourCC] { try inner.allKeys() }
}

private struct Rig {
    let rt: HelperRuntime
    let smc: FakeSMCClient
    let counter: CountingSMC
    let clock: FakeClock
    let temp: TempSource
}

private func flt(_ v: Double) -> SMCValue { SMCValue(key: "XXXX", type: "flt ", bytes: SMCValue.encode(v, as: .flt)) }
private func ui8(_ v: Double) -> SMCValue { SMCValue(key: "XXXX", type: "ui8 ", bytes: SMCValue.encode(v, as: .ui8)) }

private func make(fanCount: Int = 1, version: String = "9.9.9", catalogAvailable: Bool = true) -> Rig {
    var v: [FourCC: SMCValue] = ["FNum": ui8(Double(fanCount))]
    for i in 0..<fanCount {
        v[FourCC("F\(i)Ac")] = flt(1000); v[FourCC("F\(i)Mn")] = flt(1000); v[FourCC("F\(i)Mx")] = flt(4900)
        v[FourCC("F\(i)Tg")] = flt(1000); v[FourCC("F\(i)md")] = ui8(0)
    }
    let smc = FakeSMCClient(values: v)
    let counter = CountingSMC(smc)
    let clock = FakeClock()
    let temp = TempSource()
    let catalog = SensorCatalog(entries: [.init(match: "hid:cpu", nameEN: "CPU", nameTR: "CPU", group: .cpu,
                                                featured: true, safety: false, suspect: false)])
    let reader = SensorReader(sources: [temp], catalog: catalog, language: "en")
    let rt = HelperRuntime(fans: FanController(smc: counter), sensors: reader, now: { clock.now() }, helperVersion: version,
                           catalogAvailable: catalogAvailable)
    return Rig(rt: rt, smc: smc, counter: counter, clock: clock, temp: temp)
}

private let silentProfile = BuiltInProfiles.all().first { $0.builtIn == .silent }!
private let silentConfig = HelperConfiguration(fanModes: [0: .profile], profile: silentProfile)
private func fixed(_ rpm: Double, fans: Int = 1) -> HelperConfiguration {
    HelperConfiguration(fanModes: Dictionary(uniqueKeysWithValues: (0..<fans).map { ($0, FanMode.fixed(rpm: rpm)) }), profile: nil)
}

private func mode(_ smc: FakeSMCClient, fan: Int = 0) -> Double? { smc.values[FourCC("F\(fan)md")]?.doubleValue }
private func lastTarget(_ smc: FakeSMCClient, fan: Int = 0) -> Double? {
    smc.writes.last { $0.0 == FourCC("F\(fan)Tg") }.map { SMCValue(key: $0.0, type: "flt ", bytes: $0.1).doubleValue ?? .nan }
}
private func writeCount(_ smc: FakeSMCClient, _ key: FourCC) -> Int { smc.writes.filter { $0.0 == key }.count }

/// Connected client with the silent profile running at 75 °C (fan 0 manual at 1390).
private func running() -> Rig {
    let r = make()
    r.rt.clientConnected()
    r.rt.apply(silentConfig)
    r.temp.cpu = 75
    r.rt.tick()
    return r
}

// MARK: - Brief

@Test func startsByResettingToAuto() {
    let r = make()
    #expect(r.smc.writes.contains { $0.0 == "F0md" && $0.1 == [0] })
}

@Test func appliesProfileOnTick() {
    let r = running()
    #expect(lastTarget(r.smc) == 1390)
    #expect(mode(r.smc) == 1)
}

@Test func disconnectResetsAfterGrace() {
    let r = running()
    r.rt.clientDisconnected()
    r.clock.advance(2); r.rt.tick()
    #expect(mode(r.smc) == 1)
    r.clock.advance(2); r.rt.tick()
    #expect(mode(r.smc) == 0)
}

@Test func reconnectWithinGraceKeepsControl() {
    let r = running()
    r.rt.clientDisconnected()
    r.clock.advance(1); r.rt.clientConnected()
    r.clock.advance(4); r.rt.tick()
    #expect(mode(r.smc) == 1)
}

@Test func sleepResetsWakeReapplies() {
    let r = running()
    r.rt.willSleep()
    #expect(mode(r.smc) == 0)
    r.rt.didWake()
    r.rt.tick()
    #expect(mode(r.smc) == 1)
}

@Test func shutdownResets() {
    let r = running()
    r.rt.shutdown()
    #expect(mode(r.smc) == 0)
}

@Test func noRedundantWrites() {
    let r = running()
    let before = writeCount(r.smc, "F0Tg")
    let modeBefore = writeCount(r.smc, "F0md")
    r.clock.advance(1); r.rt.tick()
    #expect(writeCount(r.smc, "F0Tg") == before)
    #expect(writeCount(r.smc, "F0md") == modeBefore)
}

@Test func exitsWhenIdle() {
    let r = make()
    r.clock.advance(5)
    #expect(!r.rt.shouldExit)
    r.clock.advance(6)
    #expect(r.rt.shouldExit)
}

// MARK: - Rulings

@Test func writeFailureFallsBackToAutoAndContinuesWithOtherFans() {
    let r = make(fanCount: 2)
    r.rt.clientConnected()
    r.smc.failWritesFor = ["F0Tg"]
    r.rt.apply(fixed(3000, fans: 2))
    r.rt.tick()
    #expect(mode(r.smc, fan: 0) == 0)
    #expect(mode(r.smc, fan: 1) == 1)
    #expect(lastTarget(r.smc, fan: 1) == 3000)
    #expect(r.rt.snapshot().commands == [0: "auto", 1: "manual:3000"])
}

@Test func writeFailureTouchesOnlyThatFanAndBacksOff() {
    let r = make(fanCount: 2)
    r.rt.clientConnected()
    r.smc.failWritesFor = ["F1Tg"]
    r.rt.apply(fixed(3000, fans: 2))
    // Fan 0: exactly one mode write (manual) after init's reset, one target write.
    let fan0Writes = { r.smc.writes.filter { $0.0 == "F0md" || $0.0 == "F0Tg" }.map(\.1) }
    let afterApply = fan0Writes()
    #expect(mode(r.smc, fan: 0) == 1)
    #expect(mode(r.smc, fan: 1) == 0)
    #expect(r.rt.snapshot().commands == [0: "manual:3000", 1: "auto"])
    let fan1Attempts = r.counter.attempts["F1Tg"]
    r.smc.failWritesFor = []
    for _ in 0..<29 { r.clock.advance(1); r.rt.tick() }
    #expect(r.counter.attempts["F1Tg"] == fan1Attempts)   // no retry inside the back-off
    #expect(mode(r.smc, fan: 1) == 0)
    #expect(fan0Writes() == afterApply)                    // fan 0 never touched again
    r.clock.advance(1); r.rt.tick()                       // 30 s after the failure
    #expect(mode(r.smc, fan: 1) == 1)
    #expect(lastTarget(r.smc, fan: 1) == 3000)
    #expect(fan0Writes() == afterApply)
}

@Test func failedFanIsRetriedAfterBackoff() {
    let r = make()
    r.rt.clientConnected()
    r.smc.failWritesFor = ["F0Tg"]
    r.rt.apply(fixed(3000))
    #expect(mode(r.smc) == 0)
    r.smc.failWritesFor = []
    r.clock.advance(29); r.rt.tick()
    #expect(mode(r.smc) == 0)
    r.clock.advance(1); r.rt.tick()
    #expect(mode(r.smc) == 1)
    #expect(lastTarget(r.smc) == 3000)
}

@Test func failedFanWhoseAutoAlsoFailsIsUnverifiedAndOtherFansUntouched() {
    let r = make(fanCount: 2)
    r.rt.clientConnected()
    // Fan 1 gets stuck: manual mode lands, the target write fails, and so does the way back to auto.
    r.counter.reject = { key, bytes in key == "F1Tg" || (key == "F1md" && bytes == [0]) }
    r.rt.apply(fixed(3000, fans: 2))
    #expect(mode(r.smc, fan: 1) == 1)
    #expect(r.rt.snapshot().commands == [0: "manual:3000", 1: "unverified"])
    let fan0 = r.smc.writes.filter { $0.0 == "F0md" }.count
    let retries = r.counter.attempts["F1md"] ?? 0
    r.clock.advance(1); r.rt.tick()
    r.clock.advance(1); r.rt.tick()
    #expect((r.counter.attempts["F1md"] ?? 0) >= retries + 2)   // retried every tick
    #expect(r.smc.writes.filter { $0.0 == "F0md" }.count == fan0) // fan 0 left alone
    #expect(mode(r.smc, fan: 0) == 1)
    #expect(r.rt.snapshot().commands[1] == "unverified")
    r.counter.reject = nil
    r.clock.advance(1); r.rt.tick()
    #expect(mode(r.smc, fan: 1) == 0)
    #expect(r.rt.snapshot().commands == [0: "manual:3000", 1: "auto"])
}

// I1: resets whose read-back fails stay "manual" for exit purposes and are retried.

@Test func unverifiedResetBlocksExitAndIsRetriedEveryTick() {
    let r = running()
    r.smc.failWritesFor = ["F0md"]
    r.rt.clientDisconnected()
    r.clock.advance(4); r.rt.tick()                 // disconnect reset; F0md write fails
    #expect(mode(r.smc) == 1)
    #expect(r.rt.snapshot().commands == [0: "unverified"])
    for _ in 0..<10 {
        let before = r.counter.attempts["F0md"] ?? 0
        r.clock.advance(1); r.rt.tick()
        #expect((r.counter.attempts["F0md"] ?? 0) > before)
    }
    #expect(!r.rt.shouldExit)
    r.smc.failWritesFor = []
    r.clock.advance(1); r.rt.tick()
    #expect(mode(r.smc) == 0)
    #expect(r.rt.snapshot().commands.isEmpty)
    #expect(r.rt.shouldExit)                         // idle long enough since the disconnect
    let settled = r.counter.attempts["F0md"]
    r.clock.advance(1); r.rt.tick()
    #expect(r.counter.attempts["F0md"] == settled)  // retries stop once verified
}

@Test func unverifiedAtStartupBlocksExit() {
    let smc = FakeSMCClient(values: ["FNum": ui8(1), "F0Ac": flt(1000), "F0Mn": flt(1000), "F0Mx": flt(4900),
                                     "F0Tg": flt(1000), "F0md": ui8(1)])
    smc.failWritesFor = ["F0md"]
    let clock = FakeClock()
    let rt = HelperRuntime(fans: FanController(smc: smc),
                           sensors: SensorReader(sources: [], catalog: .init(entries: []), language: "en"),
                           now: { clock.now() }, helperVersion: "x")
    clock.advance(20); rt.tick()
    #expect(!rt.shouldExit)
    smc.failWritesFor = []
    rt.tick()
    #expect(rt.shouldExit)
}

@Test func trackingClearedAfterDisconnectReset() {
    let r = make()
    r.rt.clientConnected()
    r.rt.apply(fixed(3000))
    r.rt.tick()
    r.rt.clientDisconnected()
    r.clock.advance(4); r.rt.tick()
    #expect(mode(r.smc) == 0)
    let targets = writeCount(r.smc, "F0Tg")
    r.rt.clientConnected()
    r.rt.apply(fixed(3000))
    r.rt.tick()
    #expect(mode(r.smc) == 1)
    #expect(writeCount(r.smc, "F0Tg") > targets)
}

@Test func trackingClearedAfterSleepSoWakeRewritesSameCommand() {
    let r = make()
    r.rt.clientConnected()
    r.rt.apply(fixed(3000))
    r.rt.tick()
    let targets = writeCount(r.smc, "F0Tg")
    r.rt.willSleep()
    r.rt.didWake()
    r.rt.tick()
    #expect(writeCount(r.smc, "F0Tg") > targets)
    #expect(mode(r.smc) == 1)
}

@Test func configurationDroppedOnDisconnectReset() {
    let r = running()
    r.rt.clientDisconnected()
    r.clock.advance(4); r.rt.tick()
    let writes = r.smc.writes.count
    r.rt.clientConnected()           // reconnect without sending apply
    for _ in 0..<5 { r.clock.advance(1); r.rt.tick() }
    #expect(mode(r.smc) == 0)
    #expect(r.smc.writes.count == writes)
    #expect(r.rt.snapshot().commands.isEmpty)
}

@Test func clientCountNeverNegative() {
    let r = running()
    r.rt.clientDisconnected()
    r.rt.clientDisconnected()        // spurious extra disconnect
    #expect(r.rt.clientCount == 0)
    r.rt.clientConnected()
    r.rt.clientDisconnected()
    #expect(r.rt.clientCount == 0)
    r.clock.advance(4); r.rt.tick()
    #expect(mode(r.smc) == 0)
}

@Test func shouldExitWaitsWhileAFanIsManual() {
    let r = running()
    r.rt.clientDisconnected()
    r.clock.advance(11)              // no tick yet, so the fan is still manual
    #expect(!r.rt.shouldExit)
    r.rt.tick()                      // disconnect reset
    #expect(r.rt.shouldExit)
}

@Test func shouldExitNeedsNoClients() {
    let r = make()
    r.rt.clientConnected()
    r.clock.advance(30)
    #expect(!r.rt.shouldExit)
    r.rt.clientDisconnected()
    r.clock.advance(9)
    #expect(!r.rt.shouldExit)
    r.clock.advance(1)
    #expect(r.rt.shouldExit)
}

@Test func didWakeWithoutClientDoesNotReapply() {
    let r = running()
    r.rt.clientDisconnected()
    r.rt.willSleep()
    let writes = r.smc.writes.count
    r.rt.didWake()
    #expect(r.smc.writes.count == writes)
    #expect(mode(r.smc) == 0)
}

@Test func tickWhileAsleepDoesNotWrite() {
    let r = running()
    r.rt.willSleep()
    let writes = r.smc.writes.count
    r.clock.advance(1); r.rt.tick()
    r.rt.apply(fixed(3000))
    #expect(r.smc.writes.count == writes)
    #expect(mode(r.smc) == 0)
}

@Test func backwardClockJumpDoesNotDelayDisconnectReset() {
    let r = running()
    r.rt.clientDisconnected()
    r.clock.advance(-3600); r.rt.tick()
    #expect(mode(r.smc) == 0)
}

@Test func applyWithoutClientsStillResetsAfterGrace() {
    let r = make()
    r.rt.apply(fixed(3000))
    r.rt.tick()
    #expect(mode(r.smc) == 1)
    r.clock.advance(4); r.rt.tick()
    #expect(mode(r.smc) == 0)
}

@Test func resetAllToAutoDropsConfiguration() {
    let r = running()
    r.rt.resetAllToAuto()
    #expect(mode(r.smc) == 0)
    r.clock.advance(1); r.rt.tick()
    #expect(mode(r.smc) == 0)
    #expect(r.rt.snapshot().commands.isEmpty)
}

@Test func snapshotReportsStateAndVersion() {
    let r = running()
    let s = r.rt.snapshot()
    #expect(s.helperVersion == "9.9.9")
    #expect(s.commands == [0: "manual:1390"])
    #expect(s.fans.count == 1 && s.fans[0].isManual)
    #expect(s.sensors.map(\.celsius) == [75])
    #expect(!s.ceilingTripped)
}

@Test func snapshotAndConfigurationRoundTripThroughJSON() throws {
    let s = running().rt.snapshot()
    #expect(try JSONDecoder().decode(HelperSnapshot.self, from: JSONEncoder().encode(s)) == s)
    let c = HelperConfiguration(fanModes: [0: .profile, 1: .fixed(rpm: 2000), 2: .auto], profile: silentProfile)
    #expect(try JSONDecoder().decode(HelperConfiguration.self, from: JSONEncoder().encode(c)) == c)
}

// MARK: - Connection tracking (I2)

@Test func silentConnectionIsNotCounted() {
    let r = make()
    _ = ConnectionTracker(runtime: r.rt)           // accepted, never sends a message
    #expect(r.rt.clientCount == 0)
    r.clock.advance(11)
    #expect(r.rt.shouldExit)
}

@Test func firstMessageCountsOnceAndEndUncounts() {
    let r = make()
    let c = ConnectionTracker(runtime: r.rt)
    c.messageReceived()
    c.messageReceived()
    #expect(r.rt.clientCount == 1)
    c.connectionEnded()
    c.connectionEnded()                             // invalidation after interruption
    #expect(r.rt.clientCount == 0)
    c.messageReceived()                             // late message after the end
    #expect(r.rt.clientCount == 0)
}

@Test func endingANeverCountedConnectionKeepsOthersCounted() {
    let r = make()
    let app = ConnectionTracker(runtime: r.rt)
    app.messageReceived()
    let silent = ConnectionTracker(runtime: r.rt)
    silent.connectionEnded()
    #expect(r.rt.clientCount == 1)
    let other = ConnectionTracker(runtime: r.rt)
    other.connectionEnded()
    #expect(r.rt.clientCount == 1)
}

@Test func snapshotCarriesXPCFormatVersion() {
    #expect(boreasXPCFormatVersion == 3)
    #expect(running().rt.snapshot().formatVersion == boreasXPCFormatVersion)
}

@Test func snapshotFromOlderHelperDecodesWithFormatVersionZero() throws {
    let s = running().rt.snapshot()
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
    json.removeValue(forKey: "formatVersion")
    let old = try JSONDecoder().decode(HelperSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(old.formatVersion == 0)
    #expect(old.fans == s.fans)
}

@Test func snapshotFromOlderHelperDecodesNewFlagsAsFalse() throws {
    let s = running().rt.snapshot()
    var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as? [String: Any])
    #expect(json["ceilingBlind"] as? Bool == false)
    #expect(json["catalogUnavailable"] as? Bool == false)
    json.removeValue(forKey: "ceilingBlind")
    json.removeValue(forKey: "catalogUnavailable")
    let old = try JSONDecoder().decode(HelperSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    #expect(!old.ceilingBlind)
    #expect(!old.catalogUnavailable)
}

// MARK: - Final review

// I1(a): with no valid safety input the helper hands controlled fans back to Apple.
@Test func runtimeGoesAutoWhenBlindAndResumesWhenInputReturns() {
    let r = make()
    r.rt.clientConnected()
    r.rt.apply(fixed(3000))
    #expect(mode(r.smc) == 1)
    r.temp.cpu = 0                                   // invalid: no safety input at all
    for _ in 0..<5 { r.clock.advance(1); r.rt.tick() }
    #expect(mode(r.smc) == 1)
    r.clock.advance(1); r.rt.tick()                  // 6 s without input
    #expect(mode(r.smc) == 0)
    #expect(r.rt.snapshot().ceilingBlind)
    #expect(r.rt.snapshot().commands == [0: "auto"])
    r.temp.cpu = 60
    r.clock.advance(1); r.rt.tick()
    #expect(mode(r.smc) == 1)
    #expect(lastTarget(r.smc) == 3000)
    #expect(!r.rt.snapshot().ceilingBlind)
}

// I1(c): without the catalog the helper refuses manual control.
@Test func catalogUnavailableRefusesManualCommands() {
    let r = make(catalogAvailable: false)
    r.rt.clientConnected()
    let error = r.rt.apply(fixed(3000))
    #expect(error != nil)
    #expect(r.rt.apply(silentConfig) != nil)
    for _ in 0..<3 { r.clock.advance(1); r.rt.tick() }
    #expect(mode(r.smc) == 0)
    #expect(!r.smc.writes.contains { $0.0 == "F0md" && $0.1 == [1] })
    #expect(writeCount(r.smc, "F0Tg") == 0)
    let s = r.rt.snapshot()
    #expect(s.catalogUnavailable)
    #expect(s.commands.isEmpty)
    #expect(s.sensors.map(\.celsius) == [50])       // readings still reported
}

@Test func catalogAvailableAcceptsConfiguration() {
    let r = make()
    #expect(r.rt.apply(fixed(3000)) == nil)
    #expect(!r.rt.snapshot().catalogUnavailable)
}

// M1: a per-fan return to auto is read back before the fan counts as verified.
@Test func perFanAutoIsReadBackBeforeCountingAsVerified() {
    let r = make()
    r.rt.clientConnected()
    r.rt.apply(fixed(3000))
    #expect(mode(r.smc) == 1)
    r.counter.ignore = { key, bytes in key == "F0md" && bytes == [0] }   // "succeeds" but stays manual
    r.rt.apply(HelperConfiguration(fanModes: [0: .auto], profile: nil))
    #expect(mode(r.smc) == 1)
    #expect(r.rt.snapshot().commands[0] == "unverified")
    r.clock.advance(1); r.rt.tick()
    #expect(r.rt.snapshot().commands[0] == "unverified")
    #expect(!r.rt.shouldExit)
    r.counter.ignore = nil
    r.clock.advance(1); r.rt.tick()
    #expect(mode(r.smc) == 0)
    #expect(r.rt.snapshot().commands == [0: "auto"])
}

// M2: a fan whose real mode disagrees with the cached command is rewritten.
@Test func fanResetBehindTheHelpersBackIsRewritten() throws {
    let r = make()
    r.rt.clientConnected()
    r.rt.apply(fixed(3000))
    let targets = writeCount(r.smc, "F0Tg")
    try r.smc.write("F0md", bytes: [0])               // e.g. `boreasctl auto` from a terminal
    r.clock.advance(1); r.rt.tick()
    #expect(mode(r.smc) == 1)
    #expect(writeCount(r.smc, "F0Tg") == targets + 1)
    #expect(lastTarget(r.smc) == 3000)
    r.clock.advance(1); r.rt.tick()                   // agreement again: no redundant write
    #expect(writeCount(r.smc, "F0Tg") == targets + 1)
}

@Test func autoFanFoundManualIsRewritten() throws {
    let r = make(fanCount: 2)
    r.rt.clientConnected()
    r.rt.apply(HelperConfiguration(fanModes: [0: .fixed(rpm: 3000), 1: .auto], profile: nil))
    #expect(mode(r.smc, fan: 1) == 0)
    try r.smc.write("F1md", bytes: [1])
    r.clock.advance(1); r.rt.tick()
    #expect(mode(r.smc, fan: 1) == 0)
    #expect(mode(r.smc, fan: 0) == 1)
}

// Fault log: only when the unverified set changes, or once a minute while it persists.
@Test func unverifiedFaultLogIsRateLimited() {
    let r = make(fanCount: 2)
    r.rt.clientConnected()
    r.counter.reject = { key, bytes in key == "F1Tg" || (key == "F1md" && bytes == [0]) }
    r.rt.apply(fixed(3000, fans: 2))
    #expect(r.rt.snapshot().commands[1] == "unverified")
    let first = r.rt.unverifiedFaultLogCount
    #expect(first == 1)
    for _ in 0..<59 { r.clock.advance(1); r.rt.tick() }
    #expect(r.rt.unverifiedFaultLogCount == first)
    r.clock.advance(1); r.rt.tick()
    #expect(r.rt.unverifiedFaultLogCount == first + 1)
    r.counter.reject = { key, bytes in (key == "F0md" || key == "F1md") && bytes == [0] }
    r.rt.resetAllToAuto()                             // set changes to {0, 1}
    #expect(r.rt.unverifiedFaultLogCount == first + 2)
}
