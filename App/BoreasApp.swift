import AppKit
import SwiftUI

@main
struct BoreasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarPanel(model: appDelegate.model)
        } label: {
            MenuBarLabel(model: appDelegate.model)
        }
        .menuBarExtraStyle(.window)

        Window("Boreas", id: "main") {
            MainWindowContent(model: appDelegate.model)
        }
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

        Window("Settings", id: "settings") {
            SettingsView(model: appDelegate.model)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var terminating = false
    /// Another Boreas was already running: this one quits without ever talking to the helper.
    private var duplicate = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Two instances would each send their own configuration to the one helper.
        if let other = Self.otherInstance() {
            duplicate = true
            other.activate()
            NSApp.terminate(nil)
            return
        }
        model.start()
    }

    /// A running Boreas with our bundle id other than this process.
    private static func otherInstance() -> NSRunningApplication? {
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        let me = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .first { $0.processIdentifier != me && !$0.isTerminated }
    }

    /// Every quit path (Quit button, logout, shutdown) first hands the fans back to Apple.
    /// `prepareToQuit` gives the helper 2 s; termination goes ahead even if that fails.
    /// A duplicate instance never connected, so it must not reset the other instance's fans.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if duplicate { return .terminateNow }
        if terminating { return .terminateLater }
        terminating = true
        Task {
            await model.prepareToQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
