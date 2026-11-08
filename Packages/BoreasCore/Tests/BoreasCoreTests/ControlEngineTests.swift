import Testing
import Foundation
@testable import BoreasCore

@Test func autoModeIsAuto() { #expect(step(modes: [0: .auto], cpu: 99) == [0: .auto]) }
@Test func fixedClamps() { #expect(step(modes: [0: .fixed(rpm: 9000)], cpu: 50) == [0: .manual(rpm: 4900)]) }
@Test func fixedClampsLow() { #expect(step(modes: [0: .fixed(rpm: 10)], cpu: 50) == [0: .manual(rpm: 1000)]) }
@Test func missingModeIsAuto() { #expect(step(modes: [:], profile: profile(), cpu: 99) == [0: .auto]) }
@Test func silentAt75Is2950() { #expect(step(profile: profile(), cpu: 75) == [0: .manual(rpm: 2950)]) }
@Test func maxRuleWins() {
    let p = profile(rules: [Rule(id: cpuRuleID, source: .group(.cpu), curve: engineSilentCurve),
                            Rule(id: gpuRuleID, source: .group(.gpu), curve: engineSilentCurve)])
    #expect(step(profile: p, cpu: 60, gpu: 75) == [0: .manual(rpm: 2950)])
}
@Test func hysteresisLagsWhenCooling() {
    var s = EngineState()
    let p = profile(smoothing: false)
    step(profile: p, cpu: 75, state: &s, t: 0)
    #expect(step(profile: p, cpu: 73, state: &s, t: 1) == [0: .manual(rpm: 2950)])
    #expect(step(profile: p, cpu: 70, state: &s, t: 2) == [0: .manual(rpm: 2755)])
}
@Test func smoothingLimitsRise() {
    var s = EngineState()
    step(profile: profile(), cpu: 55, state: &s, t: 0)
    #expect(step(profile: profile(), cpu: 95, state: &s, t: 1) == [0: .manual(rpm: 1600)])
}
@Test func smoothingLimitsFall() {
    var s = EngineState()
    let p = profile(hyst: 0)
    step(profile: p, cpu: 95, state: &s, t: 0)
    #expect(step(profile: p, cpu: 55, state: &s, t: 1) == [0: .manual(rpm: 4600)])
}
@Test func noSmoothingWhenDtNotPositive() {
    var s = EngineState()
    step(profile: profile(), cpu: 55, state: &s, t: 5)
    #expect(step(profile: profile(), cpu: 95, state: &s, t: 5) == [0: .manual(rpm: 4900)])
    var s2 = EngineState()
    step(profile: profile(), cpu: 55, state: &s2, t: 5)
    #expect(step(profile: profile(), cpu: 95, state: &s2, t: 4) == [0: .manual(rpm: 4900)])
}
@Test func lastRPMClearedWhenAuto() {
    var s = EngineState()
    step(profile: profile(), cpu: 75, state: &s, t: 0)
    #expect(s.lastRPM[0] == 2950)
    step(modes: [0: .auto], profile: profile(), cpu: 75, state: &s, t: 1)
    #expect(s.lastRPM[0] == nil)
    // next profile step is unsmoothed
    #expect(step(profile: profile(), cpu: 95, state: &s, t: 2) == [0: .manual(rpm: 4900)])
}
@Test func missingSensorFallsBackToAuto() {
    let p = profile(rules: [Rule(source: .sensor(SensorID("smc:GONE")), curve: engineSilentCurve)])
    #expect(step(profile: p, cpu: 80) == [0: .auto])
}
@Test func invalidSensorIgnoredOtherRuleStillWorks() {
    let p = profile(rules: [Rule(id: cpuRuleID, source: .group(.cpu), curve: engineSilentCurve),
                            Rule(source: .sensor(SensorID("smc:GONE")), curve: engineSilentCurve)])
    #expect(step(profile: p, cpu: 75) == [0: .manual(rpm: 2950)])
}
@Test func invalidAndSuspectReadingsNotUsedAsSource() {
    let r = [reading("a", .cpu, .nan), reading("b", .cpu, 151), reading("c", .cpu, 120, suspect: true),
             reading("d", .cpu, 75)]
    #expect(step(profile: profile(), readings: r) == [0: .manual(rpm: 2950)])
    let p = profile(rules: [Rule(source: .sensor(SensorID("a")), curve: engineSilentCurve)])
    #expect(step(profile: p, readings: r) == [0: .auto])
}
@Test func skippedRuleKeepsHysteresisMemory() {
    var s = EngineState()
    let p = profile(smoothing: false)
    step(profile: p, cpu: 75, state: &s, t: 0)
    step(profile: p, readings: [], state: &s, t: 1)
    #expect(s.effectiveTemp[cpuRuleID] == 75)
}
@Test func releaseToAppleBelowMin() { #expect(step(profile: profile(release: true), cpu: 40) == [0: .auto]) }
@Test func automaticProfileIsAuto() { #expect(step(profile: BuiltInProfiles.all()[0], cpu: 99) == [0: .auto]) }
@Test func nilProfileIsAuto() { #expect(step(modes: [0: .profile], cpu: 99) == [0: .auto]) }

// Ceiling integration
private func sustainedState(_ temp: Double) -> EngineState {
    var s = EngineState()
    for i in 0..<5 { _ = s.ceiling.update(readings: [reading("smc:Tp01", .cpu, temp, safety: true)], now: t0.addingTimeInterval(Double(i))) }
    return s
}
@Test func ceilingForcesMaxInProfileAndFixed() {
    var s = sustainedState(105)
    let r = [reading("smc:Tp01", .cpu, 105, safety: true)]
    #expect(step(modes: [0: .fixed(rpm: 1200)], readings: r, state: &s, t: 5) == [0: .manual(rpm: 4900)])
    #expect(step(modes: [0: .profile], profile: profile(), readings: r, state: &s, t: 6) == [0: .manual(rpm: 4900)])
    #expect(s.lastRPM[0] == 4900)
}
@Test func ceilingLeavesAutoFansAuto() {
    var s = sustainedState(105)
    #expect(step(modes: [0: .auto], readings: [reading("smc:Tp01", .cpu, 105, safety: true)], state: &s, t: 5) == [0: .auto])
}
@Test func ceilingUsesAllSafetyReadings() {
    var s = EngineState()
    let r = [reading("smc:Tp01", .cpu, 60, safety: true), reading("smc:Tp02", .cpu, 105, safety: true)]
    for i in 0..<5 { step(modes: [0: .fixed(rpm: 1200)], readings: r, state: &s, t: Double(i)) }
    #expect(s.ceiling.tripped)
}
@Test func ceilingIgnoresInvalidSafetyReadings() {
    var s = EngineState()
    let r = [reading("smc:Tp01", .cpu, 70, safety: true), reading("smc:Tp02", .cpu, .nan, safety: true),
             reading("smc:Tp03", .cpu, 151, safety: true)]
    for i in 0..<6 { step(modes: [0: .fixed(rpm: 1200)], readings: r, state: &s, t: Double(i)) }
    #expect(!s.ceiling.tripped)
}
@Test func lastTickSetEveryStep() {
    var s = EngineState()
    step(modes: [:], cpu: 50, state: &s, t: 3)
    #expect(s.lastTick == t0.addingTimeInterval(3))
}

// Fix round 1
@Test func backwardClockJumpDoesNotDisableCeiling() {
    var s = EngineState()
    let low = [reading("smc:Tp01", .cpu, 50, safety: true)]
    let hot = [reading("smc:Tp01", .cpu, 140, safety: true)]
    for i in 0..<5 { step(modes: [0: .fixed(rpm: 1200)], readings: low, state: &s, t: Double(i)) }
    var tripped = false
    for i in 0..<5 {
        step(modes: [0: .fixed(rpm: 1200)], readings: hot, state: &s, t: -3600 + Double(i))
        tripped = s.ceiling.tripped
    }
    #expect(tripped)
}
@Test func backwardJumpDisablesSmoothing() {
    var s = EngineState()
    step(profile: profile(), cpu: 55, state: &s, t: 100)
    #expect(step(profile: profile(), cpu: 95, state: &s, t: 50) == [0: .manual(rpm: 4900)])
}
@Test func invalidFanInfoIsAuto() {
    let bad = [FanInfo(index: 0, actual: 0, min: 4900, max: 1000, target: 0, isManual: false),
               FanInfo(index: 0, actual: 0, min: 1000, max: .nan, target: 0, isManual: false),
               FanInfo(index: 0, actual: 0, min: 0, max: 0, target: 0, isManual: false)]
    for f in bad {
        var s = sustainedState(105)
        s.lastRPM[0] = 3000
        let r = [reading("smc:Tp01", .cpu, 105, safety: true)]
        #expect(step(modes: [0: .profile], profile: profile(), readings: r, state: &s, t: 5, fans: [f]) == [0: .auto])
        #expect(step(modes: [0: .fixed(rpm: 2000)], readings: r, state: &s, t: 6, fans: [f]) == [0: .auto])
        #expect(s.lastRPM[0] == nil)
    }
}
@Test func negativeHysteresisClampedToZero() {
    var s = EngineState()
    let p = profile(smoothing: false, hyst: -3)
    for i in 0..<4 { #expect(step(profile: p, cpu: 75, state: &s, t: Double(i)) == [0: .manual(rpm: 2950)]) }
}
@Test func nanHysteresisBehavesLikeDefault() {
    var s = EngineState()
    let p = profile(smoothing: false, hyst: .nan)
    step(profile: p, cpu: 75, state: &s, t: 0)
    #expect(step(profile: p, cpu: 73, state: &s, t: 1) == [0: .manual(rpm: 2950)])
    #expect(step(profile: p, cpu: 70, state: &s, t: 2) == [0: .manual(rpm: 2755)])
}
