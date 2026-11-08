import Foundation
import ServiceManagement

/// What the app knows about BoreasHelper's registration.
public enum HelperStatus: Equatable, Sendable {
    /// Not registered yet (or `SMAppService` reports `.notFound`, as it does on a fresh install
    /// before the first `register()`): the app offers to install it.
    case notRegistered
    case requiresApproval
    case enabled
    /// `register()` failed because the daemon plist or executable is missing from the bundle.
    case unavailable

    /// Maps `SMAppService.Status`. `.notFound` means "not registered yet" here, not "missing":
    /// only a `register()` failure that says so (`registrationMissing`) makes it `.unavailable`.
    public static func resolve(_ status: SMAppService.Status, registrationMissing: Bool) -> HelperStatus {
        let base: HelperStatus
        switch status {
        case .notRegistered, .notFound: base = .notRegistered
        case .requiresApproval: base = .requiresApproval
        case .enabled: base = .enabled
        @unknown default: base = .notRegistered
        }
        return base == .notRegistered && registrationMissing ? .unavailable : base
    }

    /// True for `register()` errors saying the plist or the executable is absent
    /// (`kSMErrorJobPlistNotFound`, `kSMErrorToolNotValid`).
    public static func isMissingRegistrationError(_ error: Error) -> Bool {
        let e = error as NSError
        let domains: Set<String> = [SMAppServiceErrorDomain, NSOSStatusErrorDomain]
        let codes: Set<Int> = [Int(kSMErrorJobPlistNotFound), Int(kSMErrorToolNotValid)]
        return domains.contains(e.domain) && codes.contains(e.code)
    }
}
