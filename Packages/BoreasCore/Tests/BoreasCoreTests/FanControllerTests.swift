import Testing
@testable import BoreasCore

private extension SMCValue {
  static func ui8(_ v: Double) -> SMCValue { SMCValue(key: "XXXX", type: "ui8 ", bytes: SMCValue.encode(v, as: .ui8)) }
  static func flt(_ v: Double) -> SMCValue { SMCValue(key: "XXXX", type: "flt ", bytes: SMCValue.encode(v, as: .flt)) }
}

private func fake(modeKey: FourCC = "F0md", extra: [FourCC: SMCValue] = [:]) -> FakeSMCClient {
  var v: [FourCC: SMCValue] = [
    "FNum": .ui8(1), "F0Ac": .flt(1920), "F0Mn": .flt(1000), "F0Mx": .flt(4900),
    "F0Tg": .flt(1935), modeKey: .ui8(0),
  ]
  for (k, x) in extra { v[k] = x }
  return FakeSMCClient(values: v)
}

@Test func readsFans() throws { let f = try FanController(smc: fake()).fans()
  #expect(f == [FanInfo(index: 0, actual: 1920, min: 1000, max: 4900, target: 1935, isManual: false)]) }
@Test func manualWritesModeThenTarget() throws { let s = fake(); try FanController(smc: s).setManual(fan: 0, rpm: 3000)
  #expect(s.writes.map(\.0) == ["F0md", "F0Tg"]); #expect(s.writes[0].1 == [1]) }
@Test func manualClampsToRange() throws { let s = fake(); try FanController(smc: s).setManual(fan: 0, rpm: 9000)
  #expect(SMCValue(key: "F0Tg", type: "flt ", bytes: s.writes[1].1).doubleValue == 4900) }
@Test func usesUppercaseModeKeyWhenThatExists() throws { let s = fake(modeKey: "F0Md"); try FanController(smc: s).setManual(fan: 0, rpm: 2000)
  #expect(s.writes.first?.0 == "F0Md") }
@Test func unlocksFtstWhenPresent() throws { let s = fake(extra: ["Ftst": .ui8(0)]); try FanController(smc: s).setManual(fan: 0, rpm: 2000)
  #expect(s.writes.first?.0 == "Ftst"); #expect(s.writes.first?.1 == [1]) }
@Test func autoClearsModeAndFtst() throws { let s = fake(extra: ["Ftst": .ui8(1)]); try FanController(smc: s).setAuto(fan: 0)
  #expect(s.writes.map(\.0) == ["F0md", "Ftst"]); #expect(s.writes.allSatisfy { $0.1 == [0] }) }
@Test func noFans() throws { #expect(try FanController(smc: FakeSMCClient(values: [:])).fans().isEmpty) }

@Test func encodesTargetWithKeyType() throws {
  let s = fake(extra: ["F0Tg": SMCValue(key: "F0Tg", type: "fpe2", bytes: [0x07, 0x8C])])
  try FanController(smc: s).setManual(fan: 0, rpm: 3000)
  #expect(SMCValue(key: "F0Tg", type: "fpe2", bytes: s.writes[1].1).doubleValue == 3000) }
@Test func ftstKeptWhileAnotherFanStaysManual() throws {
  let s = fake(extra: ["FNum": .ui8(2), "F1Ac": .flt(1), "F1Mn": .flt(1), "F1Mx": .flt(2), "F1Tg": .flt(1), "F1md": .ui8(1), "Ftst": .ui8(1)])
  try FanController(smc: s).setAuto(fan: 0)
  #expect(s.writes.map(\.0) == ["F0md"]) }
@Test func setAllAutoSwallowsErrorsAndStillClearsFtst() throws {
  let s = fake(extra: ["Ftst": .ui8(1), "F0md": .ui8(1)]); s.failWritesFor = ["F0md"]
  let left = FanController(smc: s).setAllAuto()   // must not throw/crash
  #expect(s.writes.map(\.0) == ["Ftst"]); #expect(s.writes[0].1 == [0])
  #expect(left == [0]) }
@Test func setAllAutoClearsFtstEvenWhenAnotherFanIsManual() throws {
  let s = fake(extra: ["FNum": .ui8(2), "F1Ac": .flt(1), "F1Mn": .flt(1), "F1Mx": .flt(2), "F1Tg": .flt(1), "F1md": .ui8(1), "Ftst": .ui8(1)])
  s.failWritesFor = ["F1md"]
  let left = FanController(smc: s).setAllAuto()
  #expect(s.writes.map(\.0) == ["F0md", "Ftst"]); #expect(left == [1]) }
@Test func setAllAutoRestoresAlsoFansWhenFNumUnreadable() throws {
  let s = FakeSMCClient(values: ["F0md": .ui8(1), "Ftst": .ui8(1)])
  let left = FanController(smc: s).setAllAuto(alsoFans: [0])
  #expect(s.writes.map(\.0) == ["F0md", "Ftst"]); #expect(left.isEmpty) }
@Test func setAllAutoReturnsFanWhoseModeWriteFails() throws {
  let s = fake(extra: ["F0md": .ui8(1)]); s.failWritesFor = ["F0md"]
  #expect(FanController(smc: s).setAllAuto() == [0]) }
@Test func setAllAutoWritesEveryFan() throws {
  let s = fake(extra: ["Ftst": .ui8(1)]); FanController(smc: s).setAllAuto()
  #expect(s.writes.map(\.0) == ["F0md", "Ftst"]) }
@Test func setManualWithoutModeKeyThrows() throws {
  let s = FakeSMCClient(values: ["FNum": .ui8(1), "F0Mn": .flt(1000), "F0Mx": .flt(4900), "F0Tg": .flt(1)])
  #expect(throws: SMCError.notFound("F0md")) { try FanController(smc: s).setManual(fan: 0, rpm: 2000) } }
@Test func badFanIndexThrows() throws {
  #expect(throws: SMCError.self) { try FanController(smc: fake()).setManual(fan: 3, rpm: 2000) } }

@Test func cliParsesSetWithHold() throws {
  #expect(try CLICommand.parse(["set", "0", "3500", "--hold", "20"]) == .set(fan: 0, rpm: 3500, hold: 20))
  #expect(try CLICommand.parse(["set", "0", "3500", "--hold", "120"]) == .set(fan: 0, rpm: 3500, hold: 120)) }
@Test func cliRequiresHoldAndCapsAt120() throws {
  #expect(throws: CLICommand.ParseError.self) { try CLICommand.parse(["set", "0", "3500"]) }
  #expect(throws: CLICommand.ParseError.self) { try CLICommand.parse(["set", "0", "3500", "--hold", "121"]) }
  #expect(throws: CLICommand.ParseError.self) { try CLICommand.parse(["set", "0", "3500", "--hold", "0"]) }
  #expect(throws: CLICommand.ParseError.self) { try CLICommand.parse(["set", "0", "abc", "--hold", "5"]) } }
@Test func cliParsesReadCommands() throws {
  #expect(try CLICommand.parse(["fans"]) == .fans)
  #expect(try CLICommand.parse(["keys", "F"]) == .keys(prefix: "F"))
  #expect(try CLICommand.parse(["auto"]) == .auto)
  #expect(throws: CLICommand.ParseError.self) { try CLICommand.parse(["bogus"]) } }

// M1: an unreadable mode key fails toward manual.
@Test func fansReportManualWhenModeKeyUnreadable() throws {
  let s = FakeSMCClient(values: ["FNum": .ui8(1), "F0Ac": .flt(1), "F0Mn": .flt(1000), "F0Mx": .flt(4900), "F0Tg": .flt(1)])
  let c = FanController(smc: s)
  #expect(try c.fans().first?.isManual == true)
  #expect(c.isManual(fan: 0))
  #expect(!FanController(smc: fake()).isManual(fan: 0))
  #expect(FanController(smc: fake(extra: ["F0md": .ui8(1)])).isManual(fan: 0)) }
