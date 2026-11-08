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

    /// An operation such as the automatic repair starts: sync is blocked until `finish()`.
    public func begin() { removing = true; readyGeneration = nil }

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

/// Notices a helper that is "enabled" for launchd but never answers (for example launchd refuses to
/// start it after a signing change), and allows exactly one automatic repair per app launch.
public struct HelperReachability: Sendable {
    public enum Action: Equatable, Sendable { case none, repair }

    /// Continuous snapshot failure after which the helper counts as unreachable.
    public static let threshold: Duration = .seconds(10)

    /// Failures needed in a row, besides `threshold` of elapsed time.
    public static let minimumFailures = 5

    private var failingSince: ContinuousClock.Instant?
    private var lastFailure: ContinuousClock.Instant?
    private var failureCount = 0
    private var repairUsed = false
    /// Failures went on for `threshold` while the helper is enabled; cleared by a success.
    public private(set) var isUnreachable = false
    /// Unreachable again after the one repair: the UI shows the persistent warning.
    public private(set) var showsWarning = false

    public init() {}

    /// A snapshot succeeded: the timer and any warning reset.
    public mutating func snapshotSucceeded() {
        clearStreak()
        isUnreachable = false
        showsWarning = false
    }

    private mutating func clearStreak() {
        failingSince = nil
        lastFailure = nil
        failureCount = 0
    }

    /// A snapshot failed at `now`. `.repair` is returned at most once per launch. A long gap since
    /// the previous failure (sleep, or ticks that did not run) starts the streak over, so one
    /// failure before and one after a sleep never add up to "10 seconds of failing".
    public mutating func snapshotFailed(at now: ContinuousClock.Instant, enabled: Bool,
                                        sampleInterval: Duration = .seconds(1)) -> Action {
        guard enabled else {
            clearStreak()
            isUnreachable = false
            showsWarning = false
            return .none
        }
        let maxGap = max(Duration.seconds(5), sampleInterval * 3)
        if let last = lastFailure, now - last > maxGap { clearStreak() }
        let start = failingSince ?? now
        failingSince = start
        lastFailure = now
        failureCount += 1
        guard failureCount >= Self.minimumFailures, now - start >= Self.threshold else { return .none }
        if isUnreachable { return .none }
        isUnreachable = true
        if repairUsed {
            showsWarning = true
            return .none
        }
        repairUsed = true
        return .repair
    }

    /// The repair could not run (a guard rejected it): it stays available for later.
    public mutating func repairAborted() {
        repairUsed = false
        isUnreachable = false
        showsWarning = false
        clearStreak()
    }

    /// The repair (reset, register, status refresh) is done: the failure timer starts afresh, so
    /// the warning only appears if the helper stays silent for another `threshold`.
    public mutating func repairFinished() {
        clearStreak()
        isUnreachable = false
        showsWarning = false
    }
}
