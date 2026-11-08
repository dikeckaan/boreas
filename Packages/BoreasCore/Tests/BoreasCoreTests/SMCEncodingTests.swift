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
