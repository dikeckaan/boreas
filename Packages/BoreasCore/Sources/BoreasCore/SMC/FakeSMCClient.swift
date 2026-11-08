import Foundation

public final class FakeSMCClient: SMCClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [FourCC: SMCValue]
    private var _writes: [(FourCC, [UInt8])] = []
    private var _failWrites = false
    private var _failWritesFor: Set<FourCC> = []

    public init(values: [FourCC: SMCValue]) { _values = values }

    public var values: [FourCC: SMCValue] { lock.withLock { _values } }
    public var writes: [(FourCC, [UInt8])] { lock.withLock { _writes } }
    public var failWrites: Bool {
        get { lock.withLock { _failWrites } }
        set { lock.withLock { _failWrites = newValue } }
    }

    public var failWritesFor: Set<FourCC> {
        get { lock.withLock { _failWritesFor } }
        set { lock.withLock { _failWritesFor = newValue } }
    }

    public func read(_ key: FourCC) throws -> SMCValue {
        try lock.withLock {
            guard let v = _values[key] else { throw SMCError.notFound(key) }
            return v
        }
    }

    public func write(_ key: FourCC, bytes: [UInt8]) throws {
        try lock.withLock {
            if _failWrites || _failWritesFor.contains(key) { throw SMCError.ioFailure(-1) }
            _writes.append((key, bytes))
            let type = _values[key]?.type ?? (bytes.count == 4 ? "flt " : "ui8 ")
            _values[key] = SMCValue(key: key, type: type, bytes: bytes)
        }
    }

    public func allKeys() throws -> [FourCC] {
        lock.withLock { _values.keys.sorted { $0.rawValue < $1.rawValue } }
    }
}
