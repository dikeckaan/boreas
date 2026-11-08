import Testing
import Foundation
@testable import BoreasCore

private func feed(_ c: inout SafetyCeiling, _ temp: Double, from: Int, count: Int, safety: Bool = true,
                  suspect: Bool = false, group: SensorGroup = .cpu) -> Bool {
    var tripped = false
    for i in from..<(from + count) {
        tripped = c.update(readings: [reading("x", group, temp, safety: safety, suspect: suspect)],
                           now: t0.addingTimeInterval(Double(i)))
    }
    return tripped
}

@Test func shortSpikeDoesNotTrip() {
    var c = SafetyCeiling()
    _ = feed(&c, 80, from: 0, count: 4)
    #expect(feed(&c, 120, from: 4, count: 1) == false) // avg 88
}
@Test func sustainedTrips() {
    var c = SafetyCeiling()
    #expect(feed(&c, 101, from: 0, count: 5) == true)
}
@Test func exactlyTripThresholdDoesNotTrip() {
    var c = SafetyCeiling()
    #expect(feed(&c, 100, from: 0, count: 5) == false)
}
@Test func releasesBelow90() {
    var c = SafetyCeiling()
    #expect(feed(&c, 105, from: 0, count: 5) == true)
    #expect(feed(&c, 95, from: 5, count: 5) == true)
    #expect(feed(&c, 85, from: 10, count: 5) == false)
}
@Test func exactly90DoesNotRelease() {
    var c = SafetyCeiling()
    _ = feed(&c, 105, from: 0, count: 5)
    #expect(feed(&c, 90, from: 5, count: 5) == true)
}
@Test func ceilingFallsBackToCpuGroupWhenNoSafetySensors() {
    var c = SafetyCeiling()
    #expect(feed(&c, 105, from: 0, count: 5, safety: false) == true)
    var g = SafetyCeiling()
    #expect(feed(&g, 105, from: 0, count: 5, safety: false, group: .gpu) == true)
}
@Test func fallbackIgnoresOtherGroups() {
    var c = SafetyCeiling()
    #expect(feed(&c, 105, from: 0, count: 5, safety: false, group: .battery) == false)
}
@Test func suspectSensorsIgnoredByCeiling() {
    var c = SafetyCeiling()
    #expect(feed(&c, 110, from: 0, count: 5, safety: false, suspect: true) == false)
}
@Test func noInputKeepsStateAndAddsNoSample() {
    var c = SafetyCeiling()
    _ = feed(&c, 105, from: 0, count: 5)
    #expect(c.update(readings: [], now: t0.addingTimeInterval(5)) == true)
}

// Final review I1: blind fail-safe and compiled-in safety patterns.

@Test func ceilingGoesBlindAfterWindowWithoutInput() {
    var c = SafetyCeiling()
    for i in 0...5 {
        c.update(readings: [], now: t0.addingTimeInterval(Double(i)))
        #expect(!c.blind, "t=\(i)")
    }
    c.update(readings: [], now: t0.addingTimeInterval(6))
    #expect(c.blind)
}
@Test func ceilingBlindCountsFromLastValidInput() {
    var c = SafetyCeiling()
    c.update(readings: [reading("smc:Tp01", .cpu, 60, safety: true)], now: t0)
    c.update(readings: [reading("smc:Tp01", .cpu, .nan, safety: true)], now: t0.addingTimeInterval(5))
    #expect(!c.blind)
    c.update(readings: [reading("smc:Tp01", .cpu, 0, safety: true)], now: t0.addingTimeInterval(5.5))
    #expect(c.blind)
    c.update(readings: [reading("smc:Tp01", .cpu, 60, safety: true)], now: t0.addingTimeInterval(6))
    #expect(!c.blind)
}
@Test func ceilingIgnoresNonSafetyNonCpuGpuForBlindness() {
    var c = SafetyCeiling()
    for i in 0...6 {
        c.update(readings: [reading("smc:TaLP", .other, 50)], now: t0.addingTimeInterval(Double(i)))
    }
    #expect(c.blind)
}
@Test func backwardClockJumpRestartsBlindWatch() {
    var c = SafetyCeiling()
    c.update(readings: [reading("smc:Tp01", .cpu, 60, safety: true)], now: t0)
    c.update(readings: [], now: t0.addingTimeInterval(-3600))
    #expect(!c.blind)
    c.update(readings: [], now: t0.addingTimeInterval(-3594))
    #expect(c.blind)
}
@Test func compiledSafetyPatternsMatchWithoutCatalogFlag() {
    for id in ["smc:TCMb", "smc:Tp01", "smc:Tp0g", "smc:Te05", "smc:Tg0f"] {
        #expect(SafetyCeiling.isSafety(reading(id, .other, 50)), "\(id)")
    }
    for id in ["smc:TCMbX", "smc:TPD0", "smc:TP01", "smc:TaLP", "hid:Tp01", "smc:TVMD"] {
        #expect(!SafetyCeiling.isSafety(reading(id, .other, 50)), "\(id)")
    }
    #expect(SafetyCeiling.isSafety(reading("hid:anything", .other, 50, safety: true)))
    #expect(!SafetyCeiling.isSafety(reading("smc:Tp01", .cpu, 50, safety: true, suspect: true)))
    #expect(!SafetyCeiling.isSafety(reading("smc:Tp01", .cpu, 50, safety: true, hotspot: true)))
}
@Test func ceilingTripsOnCompiledPatternWithEmptyCatalog() throws {
    final class Source: SensorSource {
        func read() -> [(id: SensorID, rawName: String, celsius: Double)] {
            [(SensorID("smc:Tp01"), "Tp01", 105), (SensorID("smc:TaLP"), "TaLP", 40)]
        }
    }
    let readings = SensorReader(sources: [Source()], catalog: SensorCatalog(entries: []), language: "en").read()
    #expect(readings.allSatisfy { !$0.safety && $0.group == .other })
    var c = SafetyCeiling()
    var tripped = false
    for i in 0..<5 { tripped = c.update(readings: readings, now: t0.addingTimeInterval(Double(i))) }
    #expect(tripped)
    #expect(!c.blind)
}
@Test func compiledPatternBeatsCpuFallback() {
    // A hot compiled-pattern sensor is used even when a cooler cpu reading exists.
    var c = SafetyCeiling()
    var tripped = false
    for i in 0..<5 {
        tripped = c.update(readings: [reading("smc:Te05", .other, 105), reading("hid:cpu", .cpu, 60)],
                           now: t0.addingTimeInterval(Double(i)))
    }
    #expect(tripped)
}
