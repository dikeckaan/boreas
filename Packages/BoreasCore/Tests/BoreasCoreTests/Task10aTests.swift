import Foundation
import Testing
@testable import BoreasCore

private func reading(_ id: String, raw: String, name: String, c: Double = 50, group: SensorGroup = .cpu,
                     suspect: Bool = false) -> SensorReading {
    SensorReading(id: SensorID(id), rawName: raw, name: name, group: group, celsius: c,
                  featured: false, safety: false, suspect: suspect)
}

// MARK: - Sensor names in the user's language

@Test func localizedNameIgnoresHelperName() {
    let catalog = SensorCatalog(entries: [
        CatalogEntry(match: "smc:TC0P", nameEN: "CPU proximity", nameTR: "CPU yakını", group: .cpu,
                     featured: true, safety: false, suspect: false),
    ])
    let r = reading("smc:TC0P", raw: "TC0P", name: "helper English name")
    #expect(catalog.localizedName(for: r, language: "tr-TR") == "CPU yakını")
    #expect(catalog.localizedName(for: r, language: "en") == "CPU proximity")
    #expect(catalog.localized(r, language: "tr").name == "CPU yakını")
    #expect(catalog.localized(r, language: "tr").celsius == 50)
}

@Test func localizedNameFallsBackToRawName() {
    let catalog = SensorCatalog(entries: [])
    let r = reading("smc:TZZZ", raw: "TZZZ", name: "whatever the helper said")
    #expect(catalog.localizedName(for: r, language: "tr") == "TZZZ")
}

@Test func localizedNameUsesNumberCapture() {
    let catalog = SensorCatalog(entries: [
        CatalogEntry(match: "hid:PMU tdie{n}", nameEN: "CPU core {n}", nameTR: "CPU çekirdek {n}", group: .cpu,
                     featured: false, safety: false, suspect: false),
    ])
    let r = reading("hid:PMU tdie3#1", raw: "PMU tdie3", name: "CPU core 3")
    #expect(catalog.localizedName(for: r, language: "tr") == "CPU çekirdek 3")
}

// MARK: - sampleInterval

@Test func normalizeClampsSampleInterval() {
    var s = AppSettings.defaults
    s.sampleInterval = 0.01
    s.normalize()
    #expect(s.sampleInterval == 0.5)
    s.sampleInterval = 60
    s.normalize()
    #expect(s.sampleInterval == 10)
    s.sampleInterval = .nan
    s.normalize()
    #expect(s.sampleInterval == 1)
    s.sampleInterval = 2
    s.normalize()
    #expect(s.sampleInterval == 2)
}

// MARK: - HistoryBuffer prunes by date

@Test func historyKeepsAtMostOneHourAtTwoSecondInterval() {
    var h = HistoryBuffer()
    let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
    // Two hours at 2 s: the date window, not the capacity, decides what stays.
    for i in 0..<3600 { h.append(HistorySample(date: base.addingTimeInterval(Double(i) * 2), values: ["cpu": Double(i)])) }
    let all = h.samples(since: .distantPast)
    let newest = base.addingTimeInterval(3599 * 2)
    #expect(all.last?.date == newest)
    #expect(all.first!.date > newest.addingTimeInterval(-3600))
    #expect(all.count == 1800)
}

@Test func historyKeepsFullHourAtHalfSecondInterval() {
    var h = HistoryBuffer()
    let base = Date(timeIntervalSinceReferenceDate: 800_000_000)
    for i in 0..<7300 { h.append(HistorySample(date: base.addingTimeInterval(Double(i) * 0.5), values: [:])) }
    #expect(h.samples(since: .distantPast).count == 7200)
}

// MARK: - FanMode Codable

private func encoded(_ m: FanMode) throws -> NSDictionary {
    try JSONSerialization.jsonObject(with: JSONEncoder().encode(m)) as! NSDictionary
}

@Test func fanModeEncodesExplicitShape() throws {
    #expect(try encoded(.auto) == ["kind": "auto"])
    #expect(try encoded(.fixed(rpm: 1800)) == ["kind": "fixed", "rpm": 1800])
    #expect(try encoded(.profile) == ["kind": "profile"])
}

@Test func fanModeRoundTrips() throws {
    for m in [FanMode.auto, .fixed(rpm: 2345.5), .profile] {
        #expect(try JSONDecoder().decode(FanMode.self, from: JSONEncoder().encode(m)) == m)
    }
}

@Test func fanModeDecodesOldSynthesizedShape() throws {
    func dec(_ s: String) throws -> FanMode { try JSONDecoder().decode(FanMode.self, from: Data(s.utf8)) }
    #expect(try dec(#"{"auto":{}}"#) == .auto)
    #expect(try dec(#"{"profile":{}}"#) == .profile)
    #expect(try dec(#"{"fixed":{"rpm":1800}}"#) == .fixed(rpm: 1800))
}

@Test func oldSettingsFileWithFanModesStillLoads() throws {
    let json = #"{"fanModes":{"0":{"fixed":{"rpm":1500}},"1":{"auto":{}},"2":{"kind":"profile"}}}"#
    let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    #expect(s.fanModes == [0: .fixed(rpm: 1500), 1: .auto, 2: .profile])
}

@Test func fanModeRejectsUnknownKind() {
    #expect(throws: (any Error).self) { try JSONDecoder().decode(FanMode.self, from: Data(#"{"kind":"bogus"}"#.utf8)) }
}

// MARK: - Temperature format

@Test func compactFormat() {
    #expect(SensorPresentation.format(62.4, unit: .celsius, compact: true) == "62°")
    #expect(SensorPresentation.format(62.4, unit: .celsius) == "62°C")
    #expect(SensorPresentation.format(62.4, unit: .fahrenheit, compact: true) == "144°")
    #expect(SensorPresentation.format(.nan, unit: .celsius, compact: true) == "–")
}

// MARK: - Profile editor helpers

@Test func moveBetweenCloseNeighboursKeepsStrictOrder() {
    let c = Curve(points: [.init(celsius: 50, fraction: 0.1), .init(celsius: 50.5, fraction: 0.2),
                           .init(celsius: 51, fraction: 0.3)])
    let m = CurveEditing.move(c, index: 1, to: .init(celsius: 80, fraction: 0.5))
    #expect(m.points[1].celsius == 50.5)
    #expect(m.points[1].fraction == 0.5)
}

@Test func moveLastPointNextToMaxKeepsStrictOrder() {
    let c = Curve(points: [.init(celsius: 109.5, fraction: 0.1), .init(celsius: 110, fraction: 0.2)])
    let m = CurveEditing.move(c, index: 1, to: .init(celsius: 20, fraction: 0.2))
    #expect(m.points[0].celsius < m.points[1].celsius)
    #expect(m.points[1].celsius <= 110)
}

@Test func sourceChoicesKeepMissingCurrentSensor() {
    let a = reading("a", raw: "A", name: "A")
    let hidden = reading("h", raw: "HRaw", name: "H")
    let prefs = SensorPrefs(hidden: [SensorID("h")])
    var out = SensorPresentation.sourceChoices(sensors: [a, hidden], prefs: prefs, current: .sensor(SensorID("gone")))
    #expect(out.sensors.map(\.id.rawValue) == ["a"])
    #expect(out.missing == "gone")
    out = SensorPresentation.sourceChoices(sensors: [a, hidden], prefs: prefs, current: .sensor(SensorID("h")))
    #expect(out.missing == "HRaw")
    #expect(out.sensors.map(\.id.rawValue) == ["a"])
    out = SensorPresentation.sourceChoices(sensors: [a], prefs: prefs, current: .sensor(SensorID("a")))
    #expect(out.missing == nil)
    out = SensorPresentation.sourceChoices(sensors: [a], prefs: prefs, current: .group(.cpu))
    #expect(out.missing == nil)
}

@Test func profileNameTakenIsTrimmedAndCaseInsensitive() {
    #expect(ProfileNaming.isTaken("  silent ", among: ["Automatic", "Silent"]))
    #expect(!ProfileNaming.isTaken("Quiet", among: ["Silent"]))
    #expect(!ProfileNaming.isTaken("   ", among: ["Silent", ""]))
}

// MARK: - Login item flag

@Test func didInitialLoginItemSetupDefaultsFalseAndPersists() throws {
    #expect(AppSettings.defaults.didInitialLoginItemSetup == false)
    #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)).didInitialLoginItemSetup == false)
    var s = AppSettings.defaults
    s.didInitialLoginItemSetup = true
    let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
    #expect(back.didInitialLoginItemSetup)
}
