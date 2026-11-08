import Foundation

public enum SMCDataType: String, Sendable {
    case flt = "flt "
    case ui8 = "ui8 "
    case ui16 = "ui16"
    case ui32 = "ui32"
    case sp78 = "sp78"
    case fpe2 = "fpe2"
    case flag = "flag"
}

public struct SMCValue: Sendable {
    public let key: FourCC
    public let type: String
    public let bytes: [UInt8]

    public init(key: FourCC, type: String, bytes: [UInt8]) {
        self.key = key
        self.type = type
        self.bytes = bytes
    }

    public var doubleValue: Double? {
        switch SMCDataType(rawValue: type) {
        case .flt:
            guard bytes.count == 4 else { return nil }
            let bits = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
            return Double(Float(bitPattern: bits))
        case .ui8, .flag:
            guard bytes.count == 1 else { return nil }
            return Double(bytes[0])
        case .ui16:
            guard bytes.count == 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
        case .ui32:
            guard bytes.count == 4 else { return nil }
            return Double(bytes.reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
        case .sp78:
            guard bytes.count == 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        case .fpe2:
            guard bytes.count == 2 else { return nil }
            return Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        case nil:
            return nil
        }
    }

    /// Clamps in Double first (NaN -> 0) so integer conversion can never trap.
    private static func clamped(_ v: Double, _ lo: Double, _ hi: Double) -> Double {
        v.isNaN ? 0 : min(max(v, lo), hi)
    }

    public static func encode(_ v: Double, as type: SMCDataType) -> [UInt8] {
        switch type {
        case .flt:
            let f = Float(clamped(v, -Double(Float.greatestFiniteMagnitude), Double(Float.greatestFiniteMagnitude)))
            let bits = f.bitPattern
            return [UInt8(bits & 0xFF), UInt8((bits >> 8) & 0xFF), UInt8((bits >> 16) & 0xFF), UInt8(bits >> 24)]
        case .ui8, .flag:
            return [UInt8(clamped(v, 0, 255).rounded())]
        case .ui16:
            let n = UInt16(clamped(v, 0, 65535).rounded())
            return [UInt8(n >> 8), UInt8(n & 0xFF)]
        case .ui32:
            let n = UInt32(clamped(v, 0, 4294967295).rounded())
            return [UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)]
        case .sp78:
            let n = UInt16(bitPattern: Int16(clamped(v * 256, -32768, 32767).rounded()))
            return [UInt8(n >> 8), UInt8(n & 0xFF)]
        case .fpe2:
            let n = UInt16(clamped(v * 4, 0, 65535).rounded())
            return [UInt8(n >> 8), UInt8(n & 0xFF)]
        }
    }
}
