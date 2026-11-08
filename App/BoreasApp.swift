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
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var terminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
    }

    /// Every quit path (Quit button, logout, shutdown) first hands the fans back to Apple.
    /// `prepareToQuit` gives the helper 2 s; termination goes ahead even if that fails.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        terminating = true
        Task {
            await model.prepareToQuit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
