/// Mirrors the C `SMCParamStruct` (80 bytes) used with the AppleSMC user client.
/// Explicit padding is required: without it the layout silently diverges from C.
struct SMCParam {
    var key: UInt32 = 0
    var vers = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt16(0))
    var pLimit = (UInt16(0), UInt16(0), UInt32(0), UInt32(0), UInt32(0))
    // dataSize, dataType, dataAttributes, then 3 bytes of trailing padding.
    var keyInfo = (UInt32(0), UInt32(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var pad: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
        UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
    ) = (
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    )
}
