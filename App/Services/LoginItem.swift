import Foundation
import ServiceManagement
import os

private let log = Logger(subsystem: "com.kaandikec.boreas", category: "loginitem")

/// Launch at login through `SMAppService.mainApp`. The system's own status is the truth: the user
/// can flip the switch in System Settings at any time.
enum LoginItem {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    /// On, or registered but waiting for approval in System Settings.
    static var isOn: Bool { status == .enabled || status == .requiresApproval }

    static func setEnabled(_ on: Bool) throws {
        let service = SMAppService.mainApp
        if on {
            if service.status != .enabled { try service.register() }
        } else if service.status == .enabled || service.status == .requiresApproval {
            try service.unregister()
        }
    }

    /// First launch only: turn launch at login on. Failure is logged and not retried; the caller
    /// records that setup happened either way, so a later launch never turns it back on.
    static func performInitialSetup() {
        do {
            try setEnabled(true)
        } catch {
            log.error("initial login item registration failed: \(String(describing: error), privacy: .public)")
        }
    }
}
