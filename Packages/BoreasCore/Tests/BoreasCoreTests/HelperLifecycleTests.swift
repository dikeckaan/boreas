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
