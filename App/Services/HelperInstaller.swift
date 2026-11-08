import AppKit
import BoreasCore
import Foundation
import ServiceManagement

/// Registers BoreasHelper with `SMAppService`. Calls run off the main actor: they talk to
/// launchd and may take a moment.
struct HelperInstaller: Sendable {
    static let plistName = "com.kaandikec.boreas.helper.plist"

    private static var service: SMAppService { .daemon(plistName: plistName) }

    /// `registrationMissing`: an earlier `register()` failed because the plist or executable is
    /// absent. See `HelperStatus.resolve` (`.notFound` alone still offers Install).
    func status(registrationMissing: Bool) async -> HelperStatus {
        await Task.detached(priority: .utility) {
            HelperStatus.resolve(Self.service.status, registrationMissing: registrationMissing)
        }.value
    }

    func register() async throws {
        try await Task.detached(priority: .userInitiated) {
            try Self.service.register()
        }.value
    }

    func unregister() async throws {
        try await Self.service.unregister()
    }

    @MainActor
    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
