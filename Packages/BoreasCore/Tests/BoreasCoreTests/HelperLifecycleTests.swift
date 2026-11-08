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

@Test func shortFailuresDoNotRepair() {
    var r = HelperReachability()
    #expect(r.snapshotFailed(at: reachT0, enabled: true) == .none)
    #expect(r.snapshotFailed(at: reachT0 + .seconds(9), enabled: true) == .none)
    #expect(!r.isUnreachable && !r.showsWarning)
}

@Test func tenSecondsOfFailuresRepairsExactlyOnce() {
    var r = HelperReachability()
    _ = r.snapshotFailed(at: reachT0, enabled: true)
    #expect(r.snapshotFailed(at: reachT0 + .seconds(10), enabled: true) == .repair)
    #expect(r.isUnreachable)
    // Further failures while the repair is pending/running do not ask again.
    #expect(r.snapshotFailed(at: reachT0 + .seconds(12), enabled: true) == .none)
    #expect(!r.showsWarning)   // the repair has not been given a chance yet
}

@Test func successResetsTheTimer() {
    var r = HelperReachability()
    _ = r.snapshotFailed(at: reachT0, enabled: true)
    _ = r.snapshotFailed(at: reachT0 + .seconds(8), enabled: true)
    r.snapshotSucceeded()
    #expect(r.snapshotFailed(at: reachT0 + .seconds(9), enabled: true) == .none)
    #expect(r.snapshotFailed(at: reachT0 + .seconds(18), enabled: true) == .none)   // only 9 s since new start
    #expect(r.snapshotFailed(at: reachT0 + .seconds(19), enabled: true) == .repair)
}

@Test func secondUnreachablePeriodWarnsWithoutRepair() {
    var r = HelperReachability()
    _ = r.snapshotFailed(at: reachT0, enabled: true)
    #expect(r.snapshotFailed(at: reachT0 + .seconds(10), enabled: true) == .repair)
    r.repairFinished()
    #expect(!r.showsWarning)
    #expect(r.snapshotFailed(at: reachT0 + .seconds(11), enabled: true) == .none)
    #expect(r.snapshotFailed(at: reachT0 + .seconds(21), enabled: true) == .none)
    #expect(r.isUnreachable && r.showsWarning)
    // Recovery clears the warning; a later outage never repairs again in this launch.
    r.snapshotSucceeded()
    #expect(!r.showsWarning)
    _ = r.snapshotFailed(at: reachT0 + .seconds(100), enabled: true)
    #expect(r.snapshotFailed(at: reachT0 + .seconds(120), enabled: true) == .none)
    #expect(r.showsWarning)
}

@Test func nonEnabledStatusNeverRepairs() {
    var r = HelperReachability()
    _ = r.snapshotFailed(at: reachT0, enabled: false)
    #expect(r.snapshotFailed(at: reachT0 + .seconds(60), enabled: false) == .none)
    #expect(!r.isUnreachable)
    // Leaving .enabled drops an earlier failure streak.
    _ = r.snapshotFailed(at: reachT0 + .seconds(61), enabled: true)
    _ = r.snapshotFailed(at: reachT0 + .seconds(65), enabled: false)
    #expect(r.snapshotFailed(at: reachT0 + .seconds(70), enabled: true) == .none)
    #expect(r.snapshotFailed(at: reachT0 + .seconds(80), enabled: true) == .repair)
}
