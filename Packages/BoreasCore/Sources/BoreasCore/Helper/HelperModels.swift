import Foundation

/// What the user wants for one fan.
public enum FanMode: Codable, Equatable, Sendable {
    case auto
    case fixed(rpm: Double)
    case profile
}

/// What the engine tells the helper to do with one fan.
public enum FanCommand: Equatable, Sendable {
    case auto
    case manual(rpm: Double)
}
