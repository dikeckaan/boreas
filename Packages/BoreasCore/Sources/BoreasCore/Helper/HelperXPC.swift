import Foundation

/// Mach service name of the BoreasHelper LaunchDaemon (also its launchd label).
public let boreasHelperMachServiceName = "com.kaandikec.boreas.helper"

/// XPC interface exported by BoreasHelper. Payloads are JSON-encoded
/// `HelperSnapshot` / `HelperConfiguration`.
@objc public protocol BoreasHelperXPC {
    /// JSON-encoded `HelperSnapshot`, or nil if encoding failed.
    func snapshot(reply: @escaping @Sendable (Data?) -> Void)
    /// `configuration` is a JSON-encoded `HelperConfiguration`. Replies nil on success,
    /// otherwise an error message.
    func apply(configuration: Data, reply: @escaping @Sendable (String?) -> Void)
    /// Puts every fan back under Apple's automatic control and drops the active configuration.
    func resetAllToAuto(reply: @escaping @Sendable () -> Void)
    func version(reply: @escaping @Sendable (String) -> Void)
}
