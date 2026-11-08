import Testing
@testable import BoreasCore

@Test func paramLayoutIs80Bytes() { #expect(MemoryLayout<SMCParam>.size == 80) }
@Test func paramOffsets() {
  #expect(MemoryLayout<SMCParam>.offset(of: \.result) == 40)
  #expect(MemoryLayout<SMCParam>.offset(of: \.data32) == 44)
  #expect(MemoryLayout<SMCParam>.offset(of: \.bytes) == 48)
}
@Test func fourCC() { #expect(FourCC("F0Ac").rawValue == 0x46304163); #expect(FourCC(rawValue: 0x46304163).description == "F0Ac") }
@Test func decodeFlt() { #expect(SMCValue(key: "F0Ac", type: "flt ", bytes: [0x00,0x00,0xF0,0x44]).doubleValue == 1920) }
@Test func decodeUi8() { #expect(SMCValue(key: "FNum", type: "ui8 ", bytes: [1]).doubleValue == 1) }
@Test func decodeSp78() { #expect(SMCValue(key: "TC0P", type: "sp78", bytes: [0x3C, 0x80]).doubleValue == 60.5) }
@Test func decodeFpe2() { #expect(SMCValue(key: "F0Ac", type: "fpe2", bytes: [0x1F, 0x40]).doubleValue == 2000) }
@Test func encodeRoundTrip() {
  for t in [SMCDataType.flt, .ui8, .ui16, .ui32, .fpe2] {
    let b = SMCValue.encode(42, as: t)
    #expect(SMCValue(key: "XXXX", type: t.rawValue, bytes: b).doubleValue == 42)
  }
}
@Test func fakeRecordsWrites() throws {
  let smc = FakeSMCClient(values: [:]); try smc.write("F0md", bytes: [1])
  #expect(smc.writes.first?.0 == "F0md")
}
@Test func fakeWriteUpdatesValues() throws {
  let smc = FakeSMCClient(values: ["F0Tg": SMCValue(key: "F0Tg", type: "flt ", bytes: [0, 0, 0, 0])])
  try smc.write("F0Tg", bytes: SMCValue.encode(1920, as: .flt))
  #expect(try smc.read("F0Tg").type == "flt ")
  #expect(try smc.read("F0Tg").doubleValue == 1920)
  try smc.write("F0md", bytes: [1])
  #expect(try smc.read("F0md").type == "ui8 ")
}
@Test func fakeMissingKeyAndFailWrites() throws {
  let smc = FakeSMCClient(values: [:])
  #expect(throws: SMCError.notFound("NOPE")) { try smc.read("NOPE") }
  smc.failWrites = true
  #expect(throws: SMCError.ioFailure(-1)) { try smc.write("F0md", bytes: [1]) }
  #expect(smc.writes.isEmpty)
}
@Test func encodeNegativeSp78RoundTrip() {
  let b = SMCValue.encode(-12.5, as: .sp78)
  #expect(SMCValue(key: "TC0P", type: "sp78", bytes: b).doubleValue == -12.5)
}
@Test func encodeClampsNonFiniteAndOutOfRange() {
  func e(_ v: Double, _ t: SMCDataType) -> [UInt8] { SMCValue.encode(v, as: t) }
  // ui8 / flag
  for t in [SMCDataType.ui8, .flag] {
    #expect(e(.infinity, t) == [255]); #expect(e(-.infinity, t) == [0])
    #expect(e(.nan, t) == [0]); #expect(e(-5, t) == [0]); #expect(e(1e30, t) == [255])
  }
  #expect(e(.infinity, .ui16) == [0xFF, 0xFF]); #expect(e(-.infinity, .ui16) == [0, 0])
  #expect(e(.nan, .ui16) == [0, 0]); #expect(e(-5, .ui16) == [0, 0]); #expect(e(1e30, .ui16) == [0xFF, 0xFF])
  #expect(e(.infinity, .ui32) == [0xFF, 0xFF, 0xFF, 0xFF]); #expect(e(-.infinity, .ui32) == [0, 0, 0, 0])
  #expect(e(.nan, .ui32) == [0, 0, 0, 0]); #expect(e(-5, .ui32) == [0, 0, 0, 0]); #expect(e(1e30, .ui32) == [0xFF, 0xFF, 0xFF, 0xFF])
  #expect(e(.infinity, .fpe2) == [0xFF, 0xFF]); #expect(e(-.infinity, .fpe2) == [0, 0])
  #expect(e(.nan, .fpe2) == [0, 0]); #expect(e(-5, .fpe2) == [0, 0]); #expect(e(1e30, .fpe2) == [0xFF, 0xFF])
  #expect(e(.infinity, .sp78) == [0x7F, 0xFF]); #expect(e(-.infinity, .sp78) == [0x80, 0x00])
  #expect(e(.nan, .sp78) == [0, 0]); #expect(e(1e30, .sp78) == [0x7F, 0xFF])
  #expect(SMCValue(key: "XXXX", type: "sp78", bytes: e(-5, .sp78)).doubleValue == -5)
  // flt: finite max magnitude, NaN -> 0
  let max = Float.greatestFiniteMagnitude
  #expect(SMCValue(key: "XXXX", type: "flt ", bytes: e(.infinity, .flt)).doubleValue == Double(max))
  #expect(SMCValue(key: "XXXX", type: "flt ", bytes: e(-.infinity, .flt)).doubleValue == -Double(max))
  #expect(e(.nan, .flt) == [0, 0, 0, 0])
  #expect(SMCValue(key: "XXXX", type: "flt ", bytes: e(-5, .flt)).doubleValue == -5)
  #expect(SMCValue(key: "XXXX", type: "flt ", bytes: e(1e30, .flt)).doubleValue == Double(Float(1e30)))
}
