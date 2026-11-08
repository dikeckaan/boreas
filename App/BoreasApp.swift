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
        .windowResizability(.contentSize)
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

/// Main window until Task 8: onboarding while the helper needs setting up, otherwise a placeholder.
private struct MainWindowContent: View {
    let model: AppModel

    var body: some View {
        if model.needsOnboarding {
            OnboardingView(model: model)
        } else {
            VStack(spacing: 10) {
                Image(systemName: "fan")
                    .font(.system(size: 36, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Boreas").font(.title2.weight(.semibold))
                Group {
                    if model.helperStatus == .unavailable, model.hasFans {
                        Text("The helper service is missing from the app. Reinstall Boreas to control fans.")
                    } else {
                        Text("The full window is coming soon. Use the menu bar to pick a profile.")
                    }
                }
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(32)
            .frame(width: 440)
        }
    }
}
