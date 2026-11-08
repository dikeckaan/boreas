import AppKit
import BoreasCore
import SwiftUI

/// The main window: onboarding while the helper is not enabled on a Mac with fans, otherwise the
/// profile bar, history chart, fans and sensors (approved mockup, right part).
struct MainWindowContent: View {
    let model: AppModel
    /// Shows "Ready" for a moment after the helper becomes enabled, before the full window.
    @State private var showReady = false

    var body: some View {
        Group {
            if model.needsOnboarding || showReady {
                OnboardingView(model: model, ready: showReady && !model.needsOnboarding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minWidth: 440)
            } else {
                MainWindow(model: model)
                    .frame(minWidth: 720, idealWidth: 800, minHeight: 440, idealHeight: 580)
            }
        }
        .onChange(of: model.needsOnboarding) { was, needed in
            guard was, !needed, model.helperStatus == .enabled else { return }
            showReady = true
            Task {
                try? await Task.sleep(for: .seconds(3))
                showReady = false
            }
        }
    }
}

struct MainWindow: View {
    let model: AppModel
    @State private var editor: EditorSession?

    /// A copy of Silent, named "New profile".
    private func newProfile() -> EditorSession {
        let silent = model.settings.profiles.first { $0.id == BuiltInProfiles.silentID } ?? BuiltInProfiles.all()[1]
        return EditorSession(profile: CurveEditing.duplicate(silent, name: String(localized: "New profile")),
                             isNew: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            HistoryChart(model: model)
            Divider()
            HStack(spacing: 0) {
                FansColumn(model: model)
                    .frame(minWidth: 300, idealWidth: 330, maxWidth: 400)
                Divider()
                SensorsColumn(model: model)
                    .frame(minWidth: 340, maxWidth: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Profile", selection: Binding(
                    get: { model.settings.activeProfileID },
                    set: { model.selectProfile($0) })) {
                    ForEach(model.settings.profiles) { p in
                        Text(p.displayName).tag(p.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(!model.canControlFans)
                .help(model.canControlFans ? "" : String(localized: "Fan control needs the helper"))
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    if let p = model.settings.activeProfile {
                        editor = EditorSession(profile: p, isNew: false)
                    }
                } label: { Label("Edit Profile", systemImage: "slider.horizontal.3") }
                    .disabled(model.settings.activeProfileID == BuiltInProfiles.automaticID)
                    .help("Edit profile")
                Button { editor = newProfile() } label: { Label("New Profile", systemImage: "plus") }
                    .help("New profile")
            }
        }
        .sheet(item: $editor) { session in
            ProfileEditor(model: model, session: session)
        }
    }
}

extension SensorGroup {
    var title: String {
        switch self {
        case .cpu: String(localized: "CPU")
        case .gpu: String(localized: "GPU")
        case .memory: String(localized: "Memory")
        case .storage: String(localized: "Storage")
        case .network: String(localized: "Network")
        case .battery: String(localized: "Battery")
        case .power: String(localized: "Power")
        case .other: String(localized: "Other")
        }
    }
}

struct ColumnHeader: View {
    let title: LocalizedStringKey
    init(_ title: LocalizedStringKey) { self.title = title }

    var body: some View {
        Text(title)
            .textCase(.uppercase)
            .font(.caption2.weight(.medium))
            .kerning(0.6)
            .foregroundStyle(.secondary)
    }
}
