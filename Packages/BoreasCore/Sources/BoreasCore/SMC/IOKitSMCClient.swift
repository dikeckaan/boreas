import Foundation
import IOKit

/// Talks to the real AppleSMC user client (selector 2, `data8` selects the operation).
public final class IOKitSMCClient: SMCClient, @unchecked Sendable {
    private enum Op: UInt8 { case read = 5, write = 6, keyByIndex = 8, keyInfo = 9 }

    private var conn: io_connect_t = 0
    private let lock = NSLock()

    public init() throws {
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard svc != 0 else { throw SMCError.ioFailure(Int32(bitPattern: UInt32(kIOReturnNotFound))) }
        defer { IOObjectRelease(svc) }
        let r = IOServiceOpen(svc, mach_task_self_, 0, &conn)
        guard r == kIOReturnSuccess else { throw SMCError.ioFailure(r) }
    }

    deinit { if conn != 0 { IOServiceClose(conn) } }

    private func call(_ input: SMCParam, key: FourCC? = nil) throws -> SMCParam {
        var inp = input
        var out = SMCParam()
        var size = MemoryLayout<SMCParam>.stride
        let r = lock.withLock {
            IOConnectCallStructMethod(conn, 2, &inp, MemoryLayout<SMCParam>.stride, &out, &size)
        }
        if r == kIOReturnNotPrivileged { throw SMCError.notPrivileged }
        guard r == kIOReturnSuccess else { throw SMCError.ioFailure(r) }
        if out.result != 0 {
            // 0x84 = key not found; anything else is a real failure and must not be masked.
            if out.result == 0x84, let key { throw SMCError.notFound(key) }
            throw SMCError.ioFailure(Int32(out.result))
        }
        return out
    }

    private func info(_ key: FourCC) throws -> (size: Int, type: FourCC) {
        var p = SMCParam(); p.key = key.rawValue; p.data8 = Op.keyInfo.rawValue
        let o = try call(p, key: key)
        return (Int(o.keyInfo.0), FourCC(rawValue: o.keyInfo.1))
    }

    public func read(_ key: FourCC) throws -> SMCValue {
        let (size, type) = try info(key)
        guard size <= 32 else { throw SMCError.badSize }
        var p = SMCParam(); p.key = key.rawValue; p.keyInfo.0 = UInt32(size); p.data8 = Op.read.rawValue
        let o = try call(p, key: key)
        let all = withUnsafeBytes(of: o.bytes) { Array($0) }
        return SMCValue(key: key, type: type.description, bytes: Array(all.prefix(size)))
    }

    public func write(_ key: FourCC, bytes: [UInt8]) throws {
        let (size, _) = try info(key)
        guard size <= 32, bytes.count == size else { throw SMCError.badSize }
        var p = SMCParam(); p.key = key.rawValue; p.keyInfo.0 = UInt32(size); p.data8 = Op.write.rawValue
        withUnsafeMutableBytes(of: &p.bytes) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
        }
        _ = try call(p, key: key)
    }

    public func allKeys() throws -> [FourCC] {
        let count = try read("#KEY")
        guard let n = count.doubleValue.map(Int.init) else { throw SMCError.badSize }
        var keys: [FourCC] = []
        for i in 0..<n {
            var p = SMCParam(); p.data8 = Op.keyByIndex.rawValue; p.data32 = UInt32(i)
            guard let o = try? call(p) else { continue }
            keys.append(FourCC(rawValue: o.key))
        }
        return keys
    }
}
