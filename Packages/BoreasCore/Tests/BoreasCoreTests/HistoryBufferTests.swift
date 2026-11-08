import Foundation
import Testing
@testable import BoreasCore

private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

private func sample(_ i: Int) -> HistorySample {
    HistorySample(date: base.addingTimeInterval(Double(i)), values: ["cpu": Double(i)])
}

@Test func historyCapacity() {
    var h = HistoryBuffer(capacity: 3)
    (0..<5).forEach { h.append(sample($0)) }
    #expect(h.samples(since: .distantPast).count == 3)
}

@Test func historyKeepsNewestInOrder() {
    var h = HistoryBuffer(capacity: 3)
    (0..<7).forEach { h.append(sample($0)) }
    #expect(h.samples(since: .distantPast).map { $0.values["cpu"] } == [4, 5, 6])
}

@Test func historySince() {
    var h = HistoryBuffer()
    (0..<10).forEach { h.append(sample($0)) }
    // Last 5 s: samples at t+5…t+9 (the bound is inclusive).
    #expect(h.samples(since: base.addingTimeInterval(5)).map { $0.values["cpu"] } == [5, 6, 7, 8, 9])
    #expect(h.samples(since: base.addingTimeInterval(100)).isEmpty)
}

@Test func historyDefaultCapacityIsOneHourAtOneHertz() {
    var h = HistoryBuffer()
    (0..<3700).forEach { h.append(sample($0)) }
    let all = h.samples(since: .distantPast)
    #expect(all.count == 3600)
    #expect(all.first?.values["cpu"] == 100)
}

@Test func historyZeroCapacityIsClampedToOne() {
    var h = HistoryBuffer(capacity: 0)
    (0..<3).forEach { h.append(sample($0)) }
    #expect(h.samples(since: .distantPast).map { $0.values["cpu"] } == [2])
}

@Test func sampleSeriesKeys() {
    func r(_ id: String, _ c: Double, _ g: SensorGroup, suspect: Bool = false) -> SensorReading {
        SensorReading(id: SensorID(id), rawName: id, name: id, group: g, celsius: c,
                      featured: false, safety: false, suspect: suspect)
    }
    let readings = [r("hid:p1", 60, .cpu), r("hid:p2", 66, .cpu), r("smc:TPD0", 120, .cpu, suspect: true),
                    r("hid:gpu", 48, .gpu), r("hid:ssd", 41, .storage)]
    let fans = [FanInfo(index: 0, actual: 2140, min: 1000, max: 5000, target: 2140, isManual: false),
                FanInfo(index: 1, actual: 2180, min: 1000, max: 5000, target: 2180, isManual: false)]
    let s = HistorySample(date: base, readings: readings, fans: fans,
                          starred: [SensorID("hid:ssd"), SensorID("hid:gone")])
    #expect(s.values == ["cpu": 66, "gpu": 48, "fan0": 2140, "fan1": 2180, "hid:ssd": 41])
}
