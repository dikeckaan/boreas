import Foundation
import Testing
@testable import BoreasCore

private struct Boom: LocalizedError { var errorDescription: String? { "boom" } }

@MainActor
private final class FakeSteps: HelperServiceSteps {
    var log: [String] = []
    var failReset = false
    var failUnregister = false
    /// Runs while a step is "in flight": a model tick that would send configuration.
    var duringStep: (() -> Void)?

    func resetAllToAuto() async throws {
        log.append("reset"); duringStep?()
        if failReset { throw Boom() }
    }
    func unregister() async throws {
        log.append("unregister"); duringStep?()
        if failUnregister { throw Boom() }
    }
}

@MainActor @Test func noApplyAfterResetDuringRemove() async {
    let life = HelperLifecycle()
    life.markReady(generation: 1)
    let steps = FakeSteps()
    var applies: [String] = []
    steps.duringStep = {
        // What a tick does: send the configuration if the gate allows it.
        if life.canSync(generation: 1) { applies.append("apply after \(steps.log.last ?? "")") }
    }
    #expect(life.canSync(generation: 1))
    let out = await life.teardown(steps, isEnabled: true, isRegistered: true, force: false)
    #expect(steps.log == ["reset", "unregister"])
    #expect(applies.isEmpty)
    #expect(out.unregistered)
    #expect(!life.canSync(generation: 1))
    // Still blocked until the caller finishes (status refresh done).
    #expect(life.removing)
    life.finish()
    #expect(!life.canSync(generation: 1))   // the old connection is not ready any more
    life.markReady(generation: 2)
    #expect(life.canSync(generation: 2))
}

@MainActor @Test func failedResetStopsRemoveUntilForced() async {
    let life = HelperLifecycle()
    let steps = FakeSteps()
    steps.failReset = true
    var out = await life.teardown(steps, isEnabled: true, isRegistered: true, force: false)
    #expect(steps.log == ["reset"])
    #expect(out.needsForce && out.resetError == "boom" && !out.unregistered)

    steps.log = []
    out = await life.teardown(steps, isEnabled: true, isRegistered: true, force: true)
    #expect(steps.log == ["reset", "unregister"])   // Remove Anyway / Reinstall go on
    #expect(!out.needsForce && out.resetError == "boom" && out.unregistered)
}

@MainActor @Test func teardownSkipsStepsThatDoNotApply() async {
    let life = HelperLifecycle()
    let steps = FakeSteps()
    _ = await life.teardown(steps, isEnabled: false, isRegistered: true, force: false)
    #expect(steps.log == ["unregister"])
    steps.log = []
    _ = await life.teardown(steps, isEnabled: false, isRegistered: false, force: false)
    #expect(steps.log.isEmpty)
    steps.failUnregister = true
    let out = await life.teardown(steps, isEnabled: false, isRegistered: true, force: false)
    #expect(out.unregisterError == "boom" && !out.unregistered)
}

@MainActor @Test func newConnectionWaitsForFirstSnapshotAndVersionCheck() {
    let life = HelperLifecycle()
    #expect(!life.canSync(generation: 1))
    life.markReady(generation: 1)
    #expect(life.canSync(generation: 1))
    #expect(!life.canSync(generation: 2))      // reconnect: not ready until it answers
    life.connectionLost()
    #expect(!life.canSync(generation: 1))
}

@Test func loginItemRegistersOnFirstRunOnly() {
    #expect(LoginItemPolicy.shouldRegisterOnThisLaunch(didInitialSetup: false, localOnly: false))
    #expect(!LoginItemPolicy.shouldRegisterOnThisLaunch(didInitialSetup: true, localOnly: false))
    #expect(!LoginItemPolicy.shouldRegisterOnThisLaunch(didInitialSetup: false, localOnly: true))
    // User turned it off after the first run: the flag stays set, so no re-registering.
    #expect(!LoginItemPolicy.shouldRegisterOnThisLaunch(didInitialSetup: true, localOnly: false))
}

// MARK: - HelperReachability

private let reachT0 = ContinuousClock.now

/// Feeds one failure per second from `from` through `to` (seconds); returns the repairs asked for.
private func feed(_ r: inout HelperReachability, from: Int, to: Int, enabled: Bool = true) -> Int {
    var repairs = 0
    for sec in from...to where r.snapshotFailed(at: reachT0 + .seconds(sec), enabled: enabled) == .repair {
        repairs += 1
    }
    return repairs
}

@Test func shortFailuresDoNotRepair() {
    var r = HelperReachability()
    #expect(feed(&r, from: 0, to: 9) == 0)
    #expect(!r.isUnreachable && !r.showsWarning)
}

@Test func rapidFailuresWithinTenSecondsDoNotRepair() {
    var r = HelperReachability()
    for ms in 0..<6 {   // six failures in 2.5 s
        #expect(r.snapshotFailed(at: reachT0 + .milliseconds(ms * 500), enabled: true) == .none)
    }
    #expect(!r.isUnreachable)
}

@Test func tenSecondsOfFailuresRepairsExactlyOnce() {
    var r = HelperReachability()
    #expect(feed(&r, from: 0, to: 9) == 0)
    #expect(r.snapshotFailed(at: reachT0 + .seconds(10), enabled: true) == .repair)
    #expect(r.isUnreachable)
    #expect(feed(&r, from: 11, to: 20) == 0)
    #expect(!r.showsWarning)   // the repair has not been given a chance yet
}

@Test func fewFailuresSpreadOverTimeDoNotRepair() {
    var r = HelperReachability()
    // Interval 5 s: four failures cover 15 s but are not yet five in a row.
    for sec in [0, 5, 10, 15] {
        #expect(r.snapshotFailed(at: reachT0 + .seconds(sec), enabled: true, sampleInterval: .seconds(5)) == .none)
    }
    #expect(r.snapshotFailed(at: reachT0 + .seconds(20), enabled: true, sampleInterval: .seconds(5)) == .repair)
}

@Test func gapFromSleepResetsTheStreak() {
    var r = HelperReachability()
    #expect(r.snapshotFailed(at: reachT0, enabled: true) == .none)
    // Mac slept 60 s: one failure before, one after must not count as 60 s of failing.
    #expect(r.snapshotFailed(at: reachT0 + .seconds(60), enabled: true) == .none)
    #expect(!r.isUnreachable)
    #expect(feed(&r, from: 61, to: 68) == 0)
    #expect(feed(&r, from: 69, to: 70) == 1)   // 10 s and 5+ failures since the gap
}

@Test func successResetsTheTimer() {
    var r = HelperReachability()
    _ = feed(&r, from: 0, to: 8)
    r.snapshotSucceeded()
    #expect(feed(&r, from: 9, to: 17) == 0)
    #expect(feed(&r, from: 18, to: 19) == 1)
}

@Test func secondUnreachablePeriodWarnsWithoutRepair() {
    var r = HelperReachability()
    #expect(feed(&r, from: 0, to: 10) == 1)
    r.repairFinished()
    #expect(!r.showsWarning)
    #expect(feed(&r, from: 11, to: 21) == 0)
    #expect(r.isUnreachable && r.showsWarning)
    r.snapshotSucceeded()
    #expect(!r.showsWarning)
    #expect(feed(&r, from: 100, to: 120) == 0)
    #expect(r.showsWarning)
}

@Test func abortedRepairKeepsTheRepairAvailable() {
    var r = HelperReachability()
    #expect(feed(&r, from: 0, to: 10) == 1)
    r.repairAborted()
    #expect(!r.isUnreachable && !r.showsWarning)
    #expect(feed(&r, from: 11, to: 21) == 1)
}

@Test func nonEnabledStatusNeverRepairs() {
    var r = HelperReachability()
    #expect(feed(&r, from: 0, to: 60, enabled: false) == 0)
    #expect(!r.isUnreachable)
    // Leaving .enabled drops an earlier failure streak.
    _ = feed(&r, from: 61, to: 65)
    _ = r.snapshotFailed(at: reachT0 + .seconds(66), enabled: false)
    #expect(feed(&r, from: 67, to: 74) == 0)
    #expect(feed(&r, from: 75, to: 80) == 1)
}
