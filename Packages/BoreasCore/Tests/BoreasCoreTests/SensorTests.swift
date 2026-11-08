import Testing
@testable import BoreasCore

private struct StubSource: SensorSource {
  let items: [(String, String, Double)]
  init(_ items: [(String, String, Double)]) { self.items = items }
  func read() -> [(id: SensorID, rawName: String, celsius: Double)] { items.map { (SensorID($0.0), $0.1, $0.2) } }
}

private func entry(_ m: String, _ en: String, group: SensorGroup = .cpu) -> CatalogEntry {
  .init(match: m, nameEN: en, nameTR: en, group: group, featured: false, safety: false, suspect: false)
}

@Test func validity() { #expect(!SensorReader.isValid(.nan)); #expect(!SensorReader.isValid(0)); #expect(!SensorReader.isValid(151)); #expect(SensorReader.isValid(62)) }
@Test func catalogGlobAndNumber() { let c = SensorCatalog(entries: [.init(match: "hid:PMU tdie{n}", nameEN: "CPU die {n}", nameTR: "CPU kalıp {n}", group: .cpu, featured: true, safety: true, suspect: false)])
  let r = SensorReader(sources: [StubSource([("hid:PMU tdie3", "PMU tdie3", 70)])], catalog: c, language: "tr").read()
  #expect(r.first?.name == "CPU kalıp 3"); #expect(r.first?.group == .cpu); #expect(r.first?.safety == true) }
@Test func unknownGoesToOtherWithRawName() { let r = SensorReader(sources: [StubSource([("smc:TZZZ", "TZZZ", 40)])], catalog: .init(entries: []), language: "en").read()
  #expect(r.first?.group == .other); #expect(r.first?.name == "TZZZ") }
@Test func invalidReadingsDropped() { let r = SensorReader(sources: [StubSource([("smc:TA0P", "TA0P", .nan)])], catalog: .init(entries: []), language: "en").read(); #expect(r.isEmpty) }
@Test func bundledCatalogDecodes() throws { #expect(try SensorCatalog.bundled().entries.count > 0) }

@Test func starMatchesAndFirstWins() {
  let c = SensorCatalog(entries: [entry("smc:Tp0*", "A"), entry("smc:Tp*", "B")])
  let r = SensorReader(sources: [StubSource([("smc:Tp01", "Tp01", 50), ("smc:Tp1x", "Tp1x", 50)])], catalog: c, language: "en").read()
  #expect(r.map(\.name) == ["A", "B"])
}
@Test func numberNeedsDigits() {
  let c = SensorCatalog(entries: [entry("hid:PMU tdie{n}", "die {n}")])
  #expect(c.match(SensorID("hid:PMU tdie")) == nil)
  #expect(c.match(SensorID("hid:PMU tdie12"))?.number == "12")
}
@Test func hidWinsOverSmcOnSameName() {
  let c = SensorCatalog(entries: [entry("hid:PMU tdie{n}", "CPU {n}"), entry("smc:Tp0{n}", "CPU {n}")])
  let r = SensorReader(sources: [StubSource([("smc:Tp01", "Tp01", 50)]), StubSource([("hid:PMU tdie1", "PMU tdie1", 60)])], catalog: c, language: "en").read()
  #expect(r.map(\.id.rawValue) == ["hid:PMU tdie1"])
}
@Test func sameSourceDuplicatesKept() {
  let c = SensorCatalog(entries: [entry("smc:Tp*", "CPU")])
  let r = SensorReader(sources: [StubSource([("smc:Tp01", "Tp01", 50), ("smc:Tp02", "Tp02", 51)])], catalog: c, language: "en").read()
  #expect(r.count == 2)
}
@Test func unmatchedSmcNotDroppedByHid() {
  let c = SensorCatalog(entries: [entry("hid:x", "X")])
  let r = SensorReader(sources: [StubSource([("smc:X", "X", 50), ("hid:x", "x", 60)])], catalog: c, language: "en").read()
  #expect(r.count == 2)
}
@Test func smcSourceCachesTemperatureKeys() throws {
  func v(_ t: String, _ x: Double, _ ty: SMCDataType) -> SMCValue { SMCValue(key: FourCC(t), type: ty.rawValue, bytes: SMCValue.encode(x, as: ty)) }
  let s = FakeSMCClient(values: ["Tp01": v("Tp01", 55, .flt), "TC0P": v("TC0P", 40.5, .sp78), "Tui8": v("Tui8", 3, .ui8), "F0Ac": v("F0Ac", 1000, .flt)])
  let r = SMCSensorSource(smc: s).read().sorted { $0.rawName < $1.rawName }
  #expect(r.map(\.rawName) == ["TC0P", "Tp01"]); #expect(r[0].celsius == 40.5); #expect(r[1].id.rawValue == "smc:Tp01")
}
@Test func cliParsesSensors() throws {
  #expect(try CLICommand.parse(["sensors"]) == .sensors(raw: false))
  #expect(try CLICommand.parse(["sensors", "--raw"]) == .sensors(raw: true))
}
