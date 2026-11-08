public enum SMCError: Error, Equatable {
    case notFound(FourCC)
    case ioFailure(Int32)
    case notPrivileged
    case badSize
}

public protocol SMCClient: AnyObject, Sendable {
    func read(_ key: FourCC) throws -> SMCValue
    func write(_ key: FourCC, bytes: [UInt8]) throws
    func allKeys() throws -> [FourCC]
}
