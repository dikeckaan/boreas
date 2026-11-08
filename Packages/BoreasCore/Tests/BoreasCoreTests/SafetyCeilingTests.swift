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
