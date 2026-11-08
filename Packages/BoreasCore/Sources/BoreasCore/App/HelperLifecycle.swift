import Foundation

/// The helper calls Remove and Reinstall make. The app implements them over `HelperClient` and
/// `SMAppService`; tests use a recording fake.
@MainActor
public protocol HelperServiceSteps {
    func resetAllToAuto() async throws
    func unregister() async throws
}

/// What `HelperLifecycle.teardown` did.
public struct TeardownOutcome: Equatable, Sendable {
    /// Message of the failed fan reset, if it failed.
    public var resetError: String?
    public var unregisterError: String?
    /// The reset failed and `force` was off: nothing was unregistered. The UI offers "Remove Anyway".
    public var needsForce: Bool
    public var unregistered: Bool
}

/// Decides when the app may talk to the helper, and the order of Remove/Reinstall.
///
/// - While `removing`, nothing may send the helper configuration (a tick in the middle of a
///   removal must not put fixed speeds back).
/// - A new connection gets configuration only after its first successful snapshot and version
///   check (`markReady`), so an old helper never sees a newer payload format.
@MainActor
public final class HelperLifecycle {
    public private(set) var removing = false
    private var readyGeneration: UInt64?

    public init() {}

    public func canSync(generation: UInt64) -> Bool {
        !removing && readyGeneration == generation
    }

    /// The connection with this generation answered a snapshot and passed the version check.
    public func markReady(generation: UInt64) { readyGeneration = generation }

    /// The connection was dropped or the helper is no longer enabled.
    public func connectionLost() { readyGeneration = nil }

    /// Fans to Apple, then unregister. `removing` stays set until `finish()`, so the caller can
    /// refresh the status (and register again, for Reinstall) before syncing resumes.
    ///
    /// The reset is the last helper call before `unregister`. If it fails: with `force` false the
    /// unregister is skipped (`needsForce`); with `force` true unregistering goes ahead anyway
    /// (launchd's SIGTERM makes the helper hand the fans back on exit).
    public func teardown(_ steps: HelperServiceSteps, isEnabled: Bool, isRegistered: Bool,
                         force: Bool) async -> TeardownOutcome {
        removing = true
        readyGeneration = nil
        var out = TeardownOutcome(resetError: nil, unregisterError: nil, needsForce: false, unregistered: false)
        if isEnabled {
            do { try await steps.resetAllToAuto() } catch {
                out.resetError = error.localizedDescription
                if !force {
                    out.needsForce = true
                    return out
                }
            }
        }
        if isRegistered {
            do {
                try await steps.unregister()
                out.unregistered = true
            } catch {
                out.unregisterError = error.localizedDescription
            }
        }
        return out
    }

    /// Syncing may resume (after the status refresh that follows a removal).
    public func finish() { removing = false }
}

public enum LoginItemPolicy {
    /// Launch at login is registered on the very first run only. Once `didInitialSetup` is
    /// recorded (also what remembers that the user turned it off), it is never done again.
    public static func shouldRegisterOnThisLaunch(didInitialSetup: Bool, localOnly: Bool) -> Bool {
        !localOnly && !didInitialSetup
    }
}
