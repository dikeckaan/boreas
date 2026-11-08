import Foundation

public struct FanInfo: Codable, Sendable, Equatable {
    public let index: Int
    public let actual: Double
    public let min: Double
    public let max: Double
    public let target: Double
    public let isManual: Bool

    public init(index: Int, actual: Double, min: Double, max: Double, target: Double, isManual: Bool) {
        self.index = index; self.actual = actual; self.min = min; self.max = max
        self.target = target; self.isManual = isManual
    }
}

public final class FanController: @unchecked Sendable {
    private let smc: SMCClient
    private static let unlockKey: FourCC = "Ftst"

    public init(smc: SMCClient) { self.smc = smc }

    public var fanCount: Int {
        guard let v = try? smc.read("FNum"), let d = v.doubleValue else { return 0 }
        return Swift.max(0, Int(d))
    }

    public func fans() throws -> [FanInfo] {
        try (0..<fanCount).map { i in
            FanInfo(
                index: i,
                actual: try number("F\(i)Ac"),
                min: try number("F\(i)Mn"),
                max: try number("F\(i)Mx"),
                target: try number("F\(i)Tg"),
                isManual: isManual(fan: i))
        }
    }

    /// Whether the fan is under manual control. An unreadable mode key counts as manual, so callers
    /// that verify a return to auto never take "unknown" for "auto".
    public func isManual(fan: Int) -> Bool {
        guard let mode = try? modeKey(for: fan), let v = try? smc.read(mode).doubleValue else { return true }
        return v != 0
    }

    public func setManual(fan: Int, rpm: Double) throws {
        guard fan >= 0, fan < fanCount else { throw SMCError.notFound(FourCC("F\(fan)Ac")) }
        let mode = try modeKey(for: fan)
        let lo = try number("F\(fan)Mn"), hi = try number("F\(fan)Mx")
        let targetKey = FourCC("F\(fan)Tg")
        let targetType = try smc.read(targetKey).type
        guard let dt = SMCDataType(rawValue: targetType) else { throw SMCError.badSize }
        let clamped = Swift.min(Swift.max(rpm.isNaN ? lo : rpm, lo), hi)

        if (try? smc.read(Self.unlockKey)) != nil {
            try smc.write(Self.unlockKey, bytes: [1])
        }
        try smc.write(mode, bytes: [1])
        try smc.write(targetKey, bytes: SMCValue.encode(clamped, as: dt))
    }

    public func setAuto(fan: Int) throws {
        let mode = try modeKey(for: fan)
        try smc.write(mode, bytes: [0])
        try clearUnlockIfNoManualFans()
    }

    /// Never throws. Tries every fan (plus `alsoFans`, even if FNum is unreadable), swallows
    /// per-fan errors, writes Ftst=0 unconditionally when the key exists, then reads back.
    /// Returns the fan indices still manual or unverifiable.
    @discardableResult
    public func setAllAuto(alsoFans: [Int] = []) -> [Int] {
        let indices = Set(0..<fanCount).union(alsoFans).sorted()
        for i in indices {
            if let mode = try? modeKey(for: i) { try? smc.write(mode, bytes: [0]) }
        }
        if (try? smc.read(Self.unlockKey)) != nil { try? smc.write(Self.unlockKey, bytes: [0]) }
        return indices.filter(isManual(fan:))
    }

    private func clearUnlockIfNoManualFans() throws {
        guard (try? smc.read(Self.unlockKey)) != nil else { return }
        let anyManual = ((try? fans()) ?? []).contains { $0.isManual }
        if !anyManual { try smc.write(Self.unlockKey, bytes: [0]) }
    }

    private func number(_ key: String) throws -> Double {
        guard let d = try smc.read(FourCC(key)).doubleValue else { throw SMCError.badSize }
        return d
    }

    private func modeKey(for fan: Int) throws -> FourCC {
        for k in ["F\(fan)md", "F\(fan)Md"] {
            let key = FourCC(k)
            if (try? smc.read(key)) != nil { return key }
        }
        throw SMCError.notFound(FourCC("F\(fan)md"))
    }
}
