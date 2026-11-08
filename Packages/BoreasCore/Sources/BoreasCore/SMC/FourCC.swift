public struct FourCC: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// Uses the first four bytes of `s`; shorter strings are padded with spaces.
    public init(_ s: String) {
        var v: UInt32 = 0
        var bytes = Array(s.utf8.prefix(4))
        while bytes.count < 4 { bytes.append(0x20) }
        for b in bytes { v = (v << 8) | UInt32(b) }
        rawValue = v
    }

    public init(stringLiteral value: String) { self.init(value) }

    public var description: String {
        let bytes = (0..<4).map { UInt8((rawValue >> UInt32(24 - 8 * $0)) & 0xFF) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
