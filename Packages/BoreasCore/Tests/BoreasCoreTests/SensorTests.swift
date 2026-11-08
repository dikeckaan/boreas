import Foundation
import Testing
@testable import BoreasCore

private struct StubSource: SensorSource {
  let items: [(String, String, Double)]
  init(_ items: [(String, String, Double)]) { self.items = items }
  func read() -> [(id: SensorID, rawName: String, celsius: Double)] { items.map { (SensorID($0.0), $0.1, $0.2) } }
}

private func entry(_ m: String, _ en: String, group: SensorGroup = .cpu, point: String? = nil) -> CatalogEntry {
  .init(match: m, nameEN: en, nameTR: en, group: group, featured: false, safety: false, suspect: false, point: point)
}

@Test func validity() { #expect(!SensorReader.isValid(.nan)); #expect(!SensorReader.isValid(0)); #expect(!SensorReader.isValid(151)); #expect(SensorReader.isValid(62)) }
@Test func catalogGlobAndNumber() { let c = SensorCatalog(entries: [.init(match: "hid:PMU tdie{n}", nameEN: "CPU die {n}", nameTR: "CPU kalıp {n}", group: .cpu, featured: true, safety: true, suspect: false)])
  let r = SensorReader(sources: [StubSource([("hid:PMU tdie3", "PMU tdie3", 70)])], catalog: c, language: "tr").read()
  #expect(r.first?.name == "CPU kalıp 3"); #expect(r.first?.group == .cpu); #expect(r.first?.safety == true) }
@Test func unknownGoesToOtherWithRawName() { let r = SensorReader(sources: [StubSource([("smc:TZZZ", "TZZZ", 40)])], catalog: .init(entries: []), language: "en").read()
  #expect(r.first?.group == .other); #expect(r.first?.name == "TZZZ") }
@Test func invalidReadingsDropped() { let r = SensorReader(sources: [StubSource([("smc:TA0P", "TA0P", .nan)])], catalog: .init(entries: []), language: "en").read(); #expect(r.isEmpty) }
@Test func bundledCatalogDecodes() throws { #expect(try SensorCatalog.bundled().entries.count > 0) }
@Test func missingCatalogBundleThrowsInsteadOfTrapping() {
  #expect(throws: CocoaError.self) { try SensorCatalog.bundled(searching: []) }
  #expect(throws: CocoaError.self) { try SensorCatalog.bundled(searching: [URL(fileURLWithPath: "/nonexistent")]) }
}

@Test func starMatchesAndFirstWins() {
  let c = SensorCatalog(entries: [entry("smc:Tp0*", "A"), entry("smc:Tp*", "B")])
  let r = SensorReader(sources: [StubSource([("smc:Tp01", "Tp01", 50), ("smc:Tp1x", "Tp1x", 50)])], catalog: c, language: "en").read()
  #expect(r.map(\.name) == ["A (Tp01)", "B (Tp1x)"])
}
@Test func numberNeedsDigits() {
  let c = SensorCatalog(entries: [entry("hid:PMU tdie{n}", "die {n}")])
  #expect(c.match(SensorID("hid:PMU tdie")) == nil)
  #expect(c.match(SensorID("hid:PMU tdie12"))?.number == "12")
}
@Test func hidWinsOverSmcOnSamePoint() {
  let c = SensorCatalog(entries: [entry("hid:PMU tdie{n}", "CPU {n}", point: "p"), entry("smc:Tp0{n}", "Other name", point: "p")])
  let r = SensorReader(sources: [StubSource([("smc:Tp01", "Tp01", 50)]), StubSource([("hid:PMU tdie1#54504d62", "PMU tdie1", 60)])], catalog: c, language: "en").read()
  #expect(r.map(\.id.rawValue) == ["hid:PMU tdie1#54504d62"])
}
@Test func sameNameWithoutPointIsNotDeduped() {
  let c = SensorCatalog(entries: [entry("hid:PMU tdie{n}", "CPU {n}"), entry("smc:Tp0{n}", "CPU {n}")])
  let r = SensorReader(sources: [StubSource([("smc:Tp01", "Tp01", 50), ("hid:PMU tdie1#1", "PMU tdie1", 60)])], catalog: c, language: "en").read()
  #expect(r.count == 2)
}
@Test func samePointSameSourceKept() {
  let c = SensorCatalog(entries: [entry("smc:TH0*", "SSD", point: "ssd")])
  let r = SensorReader(sources: [StubSource([("smc:TH0a", "TH0a", 50), ("smc:TH0b", "TH0b", 51)])], catalog: c, language: "en").read()
  #expect(r.count == 2)
}
@Test func hidSuffixIgnoredByCatalogMatch() {
  let c = SensorCatalog(entries: [entry("hid:PMU tdie{n}", "die {n}")])
  #expect(c.match(SensorID("hid:PMU tdie1#54504d62"))?.number == "1")
  #expect(c.match(SensorID("hid:PMU tdie1#54504d62-2"))?.number == "1")
}
@Test func wildcardNamesGetRawSuffix() {
  let c = SensorCatalog(entries: [entry("smc:Tg*", "GPU cluster"), entry("hid:PMU tdie{n}", "die {n}")])
  let r = SensorReader(sources: [StubSource([("smc:Tg0a", "Tg0a", 50), ("hid:PMU tdie3#1", "PMU tdie3", 60)])], catalog: c, language: "en").read()
  #expect(r.map(\.name) == ["GPU cluster (Tg0a)", "die 3"])
}
@Test func liveHidIdsAreDistinctAndStable() {
  let src = HIDSensorSource()
  let a = src.read().map(\.id), b = src.read().map(\.id)
  #expect(Set(a).count == a.count)
  #expect(a == b)
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
private final class CountingSMC: SMCClient, @unchecked Sendable {
  let inner: FakeSMCClient
  private let lock = NSLock()
  private var _calls = 0, _failures: Int
  init(_ inner: FakeSMCClient, failFirst: Int = 0) { self.inner = inner; _failures = failFirst }
  var allKeysCalls: Int { lock.withLock { _calls } }
  func read(_ key: FourCC) throws -> SMCValue { try inner.read(key) }
  func write(_ key: FourCC, bytes: [UInt8]) throws { try inner.write(key, bytes: bytes) }
  func allKeys() throws -> [FourCC] {
    try lock.withLock {
      _calls += 1
      if _failures > 0 { _failures -= 1; throw SMCError.ioFailure(-1) }
    }
    return try inner.allKeys()
  }
}
private func tempFake() -> FakeSMCClient {
  func v(_ t: String, _ x: Double, _ ty: SMCDataType) -> SMCValue { SMCValue(key: FourCC(t), type: ty.rawValue, bytes: SMCValue.encode(x, as: ty)) }
  return FakeSMCClient(values: ["Tp01": v("Tp01", 55, .flt), "TC0P": v("TC0P", 40.5, .sp78), "Tui8": v("Tui8", 3, .ui8), "F0Ac": v("F0Ac", 1000, .flt)])
}
@Test func smcSourceFiltersAndCachesKeys() throws {
  let s = CountingSMC(tempFake())
  let src = SMCSensorSource(smc: s)
  let r = src.read().sorted { $0.rawName < $1.rawName }
  #expect(r.map(\.rawName) == ["TC0P", "Tp01"]); #expect(r[0].celsius == 40.5); #expect(r[1].id.rawValue == "smc:Tp01")
  _ = src.read(); _ = src.read()
  #expect(s.allKeysCalls == 1)
}
@Test func smcSourceRetriesFailedDiscovery() throws {
  let s = CountingSMC(tempFake(), failFirst: 1)
  let src = SMCSensorSource(smc: s)
  #expect(src.read().isEmpty)
  #expect(src.read().count == 2)
  #expect(s.allKeysCalls == 2)
  _ = src.read()
  #expect(s.allKeysCalls == 2)
}
@Test func cliParsesSensors() throws {
  #expect(try CLICommand.parse(["sensors"]) == .sensors(raw: false))
  #expect(try CLICommand.parse(["sensors", "--raw"]) == .sensors(raw: true))
}

@Test func bundledCatalogSafetyAndFeaturedRules() throws {
  let e = try SensorCatalog.bundled().entries
  #expect(e.filter { $0.match.hasPrefix("hid:PMU tdie") }.allSatisfy { !$0.safety })
  #expect(e.contains { $0.safety && $0.group == .cpu })
  #expect(e.contains { $0.safety && $0.group == .gpu })
  #expect(e.filter(\.featured).count <= 8)
}

@Test func bundledCatalogMarksTdieAsHotspot() throws {
    let entries = try SensorCatalog.bundled().entries
    let tdie = entries.filter { $0.match.hasPrefix("hid:PMU tdie") }
    #expect(tdie.count == 3)
    #expect(tdie.allSatisfy { $0.hotspot })
    #expect(entries.filter { !$0.match.hasPrefix("hid:PMU tdie") }.allSatisfy { !$0.hotspot })
}
@Test func readingDecodesWithoutHotspotKey() throws {
    let json = #"{"id":"smc:TCMb","rawName":"TCMb","name":"x","group":"cpu","celsius":50,"featured":false,"safety":false,"suspect":false}"#
    let r = try JSONDecoder().decode(SensorReading.self, from: Data(json.utf8))
    #expect(r.hotspot == false)
}

// Final review I1(c): the helper learns whether the catalog loaded.
@Test func liveReaderReportsWhetherCatalogLoaded() {
  #expect(!SensorReader.live(language: "en", catalogSearchPaths: []).catalogLoaded)
  #expect(SensorReader.live(language: "en").catalogLoaded)
}
