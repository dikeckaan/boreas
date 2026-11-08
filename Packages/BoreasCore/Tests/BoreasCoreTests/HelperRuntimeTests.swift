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

private struct Rig {
    let rt: HelperRuntime
    let smc: FakeSMCClient
    let clock: FakeClock
    let temp: TempSource
}

private func flt(_ v: Double) -> SMCValue { SMCValue(key: "XXXX", type: "flt ", bytes: SMCValue.encode(v, as: .flt)) }
private func ui8(_ v: Double) -> SMCValue { SMCValue(key: "XXXX", type: "ui8 ", bytes: SMCValue.encode(v, as: .ui8)) }

private func make(fanCount: Int = 1, version: String = "9.9.9") -> Rig {
    var v: [FourCC: SMCValue] = ["FNum": ui8(Double(fanCount))]
    for i in 0..<fanCount {
        v[FourCC("F\(i)Ac")] = flt(1000); v[FourCC("F\(i)Mn")] = flt(1000); v[FourCC("F\(i)Mx")] = flt(4900)
        v[FourCC("F\(i)Tg")] = flt(1000); v[FourCC("F\(i)md")] = ui8(0)
    }
    let smc = FakeSMCClient(values: v)
    let clock = FakeClock()
    let temp = TempSource()
    let catalog = SensorCatalog(entries: [.init(match: "hid:cpu", nameEN: "CPU", nameTR: "CPU", group: .cpu,
                                                featured: true, safety: false, suspect: false)])
    let reader = SensorReader(sources: [temp], catalog: catalog, language: "en")
    let rt = HelperRuntime(fans: FanController(smc: smc), sensors: reader, now: { clock.now() }, helperVersion: version)
    return Rig(rt: rt, smc: smc, clock: clock, temp: temp)
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

/// Connected client with the silent profile running at 75 °C (fan 0 manual at 2950).
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
    #expect(lastTarget(r.smc) == 2950)
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

@Test func writeFailureOnLaterFanRestoresEarlierFansInSameTick() {
    // setAllAuto resets every fan; fans already written this tick must be rewritten.
    let r = make(fanCount: 2)
    r.rt.clientConnected()
    r.smc.failWritesFor = ["F1Tg"]
    r.rt.apply(fixed(3000, fans: 2))
    r.rt.tick()
    #expect(mode(r.smc, fan: 0) == 1)
    #expect(mode(r.smc, fan: 1) == 0)
    #expect(r.rt.snapshot().commands == [0: "manual:3000", 1: "auto"])
}

@Test func failedFanIsRetriedOnceWritesWorkAgain() {
    let r = make()
    r.rt.clientConnected()
    r.smc.failWritesFor = ["F0Tg"]
    r.rt.apply(fixed(3000))
    r.rt.tick()
    #expect(mode(r.smc) == 0)
    r.smc.failWritesFor = []
    r.clock.advance(1); r.rt.tick()
    #expect(mode(r.smc) == 1)
    #expect(lastTarget(r.smc) == 3000)
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
    #expect(s.commands == [0: "manual:2950"])
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
