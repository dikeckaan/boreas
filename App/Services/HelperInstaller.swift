import AppKit
import Foundation
import ServiceManagement

enum HelperStatus: Equatable, Sendable {
    case notRegistered
    case requiresApproval
    case enabled
    /// The daemon plist is not in the app bundle (`SMAppService.Status.notFound`).
    case unavailable
}

/// Registers BoreasHelper with `SMAppService`. Calls run off the main actor: they talk to
/// launchd and may take a moment.
struct HelperInstaller: Sendable {
    static let plistName = "com.kaandikec.boreas.helper.plist"

    private static var service: SMAppService { .daemon(plistName: plistName) }

    func status() async -> HelperStatus {
        await Task.detached(priority: .utility) {
            switch Self.service.status {
            case .notRegistered: HelperStatus.notRegistered
            case .requiresApproval: .requiresApproval
            case .enabled: .enabled
            case .notFound: .unavailable
            @unknown default: .unavailable
            }
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
