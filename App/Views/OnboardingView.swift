import AppKit
import BoreasCore
import SwiftUI

/// Shown in the main window while the helper is not registered or awaits approval, on Macs with
/// fans only.
struct OnboardingView: View {
    let model: AppModel
    /// The helper just became enabled: confirmation shown for a moment before the main window.
    var ready = false
    @State private var working = false

    var body: some View {
        if ready {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.green)
                Text("Ready — fan control is on")
                    .font(.title2.weight(.semibold))
            }
            .padding(32)
            .frame(width: 440)
        } else {
            setup
        }
    }

    private var setup: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)
            Text("Set Up Fan Control")
                .font(.title2.weight(.semibold))
            Text("To change fan speeds, Boreas needs a small helper service with administrator rights. It runs only while Boreas is open, gives every fan back to Apple's automatic control when Boreas quits or the Mac sleeps, and accepts commands from Boreas alone. Temperatures can be read without it.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)

            switch model.helperStatus {
            case .unavailable:
                // Only after register() reported the plist or executable missing; the error follows below.
                Text("The helper service is missing from the app. Reinstall Boreas to control fans.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            case .requiresApproval:
                Text("Allow Boreas under System Settings › General › Login Items & Extensions.")
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open System Settings") { model.openSystemSettings() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            default:
                if !AppInstallLocation.isInApplications(Bundle.main.bundleURL) {
                    VStack(spacing: 6) {
                        Label("Move Boreas to the Applications folder first", systemImage: "folder")
                            .font(.callout)
                            .multilineTextAlignment(.center)
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }
                    }
                }
                Button {
                    working = true
                    Task {
                        await model.installHelper()
                        working = false
                    }
                } label: {
                    Text("Install Helper")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(working)
            }

            if let error = model.installError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(32)
        .frame(width: 440)
    }
}
