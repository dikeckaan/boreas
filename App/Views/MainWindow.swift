import AppKit
import BoreasCore
import SwiftUI

/// The main window: onboarding while the helper is not enabled on a Mac with fans, otherwise the
/// profile bar, history chart, fans and sensors (approved mockup, right part).
struct MainWindowContent: View {
    let model: AppModel
    /// Shows "Ready" for a moment after the helper becomes enabled, before the full window.
    @State private var showReady = false
    /// False while the window is closed, minimised, covered or on another Space: the live views are
    /// not built then (see `trackWindowVisibility`).
    @State private var isVisible = true

    var body: some View {
        Group {
            if model.needsOnboarding || showReady {
                if isVisible {
                    OnboardingView(model: model, ready: showReady && !model.needsOnboarding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(minWidth: 440)
                } else {
                    Color.clear.frame(minWidth: 440, minHeight: 300)
                }
            } else {
                MainWindow(model: model, isVisible: isVisible)
                    .frame(minWidth: 720, idealWidth: 800, minHeight: 440, idealHeight: 580)
            }
        }
        .trackWindowVisibility($isVisible)
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
    /// The live parts (chart, fans, sensors) are only built while the window can be seen. The
    /// window itself, its toolbar and an open profile editor sheet stay, so nothing is lost when
    /// another window covers it.
    let isVisible: Bool
    @State private var editor: EditorSession?

    /// A copy of Silent, named "New profile".
    private func newProfile() -> EditorSession {
        let silent = model.settings.profiles.first { $0.id == BuiltInProfiles.silentID } ?? BuiltInProfiles.all()[1]
        return EditorSession(profile: CurveEditing.duplicate(silent, name: String(localized: "New profile")),
                             isNew: true)
    }

    var body: some View {
        VStack(spacing: 0) {
            if isVisible {
                HistoryChart(model: model)
                Divider()
                HStack(spacing: 0) {
                    FansColumn(model: model)
                        .frame(minWidth: 300, idealWidth: 330, maxWidth: 400)
                    Divider()
                    SensorsColumn(model: model)
                        .frame(minWidth: 340, maxWidth: .infinity)
                }
            } else {
                Color.clear
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
    let title: LocalizedStringResource
    init(_ title: LocalizedStringResource) { self.title = title }

    var body: some View {
        // Upper-cased here, by the app language's rules, rather than with `.textCase`.
        Text(verbatim: AppLanguage.uppercased(title))
            .font(.caption2.weight(.medium))
            .kerning(0.6)
            .foregroundStyle(.secondary)
    }
}
