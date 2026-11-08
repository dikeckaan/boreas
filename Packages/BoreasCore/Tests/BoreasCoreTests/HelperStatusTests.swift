import Foundation
import ServiceManagement
import Testing
@testable import BoreasCore

@Test func statusMapping() {
    #expect(HelperStatus.resolve(.notRegistered, registrationMissing: false) == .notRegistered)
    #expect(HelperStatus.resolve(.requiresApproval, registrationMissing: false) == .requiresApproval)
    #expect(HelperStatus.resolve(.enabled, registrationMissing: false) == .enabled)
}

@Test func notFoundOffersInstall() {
    // A fresh install reports .notFound before the first register(): it must lead to onboarding.
    #expect(HelperStatus.resolve(.notFound, registrationMissing: false) == .notRegistered)
}

@Test func missingOnlyAfterRegisterFailedThatWay() {
    #expect(HelperStatus.resolve(.notFound, registrationMissing: true) == .unavailable)
    #expect(HelperStatus.resolve(.notRegistered, registrationMissing: true) == .unavailable)
    // A real registration state wins over an earlier failure.
    #expect(HelperStatus.resolve(.requiresApproval, registrationMissing: true) == .requiresApproval)
    #expect(HelperStatus.resolve(.enabled, registrationMissing: true) == .enabled)
}

@Test func registerErrorsMeaningMissing() {
    let plistMissing = NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorJobPlistNotFound))
    let toolInvalid = NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorToolNotValid))
    let osStatus = NSError(domain: NSOSStatusErrorDomain, code: Int(kSMErrorJobPlistNotFound))
    #expect(HelperStatus.isMissingRegistrationError(plistMissing))
    #expect(HelperStatus.isMissingRegistrationError(toolInvalid))
    #expect(HelperStatus.isMissingRegistrationError(osStatus))

    let denied = NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorLaunchDeniedByUser))
    let signature = NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorInvalidSignature))
    let unrelated = NSError(domain: NSCocoaErrorDomain, code: Int(kSMErrorJobPlistNotFound))
    #expect(!HelperStatus.isMissingRegistrationError(denied))
    #expect(!HelperStatus.isMissingRegistrationError(signature))
    #expect(!HelperStatus.isMissingRegistrationError(unrelated))
}
