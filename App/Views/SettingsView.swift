import AppKit
import BoreasCore
import ServiceManagement
import SwiftUI

/// Spec §5.4: launch at login, menu bar display, unit, sampling interval and the helper service.
struct SettingsView: View {
    let model: AppModel
    @State private var launchAtLogin = LoginItem.isOn
    @State private var loginStatus = LoginItem.status
    @State private var loginError: String?
    @State private var working = false
    @State private var confirmRemove = false

    private static let intervalChoices: [Double] = [1, 2, 5]

    var body: some View {
        Form {
            Section {
                Toggle("Launch Boreas at login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                    .disabled(AppModel.localOnly)
                if loginStatus == .requiresApproval {
                    Text("Allow Boreas under System Settings › General › Login Items & Extensions.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Menu bar") {
                Picker("Show", selection: Binding(get: { model.settings.menuBarDisplay },
                                                  set: { model.settings.menuBarDisplay = $0 })) {
                    Text("Icon only").tag(MenuBarDisplay.iconOnly)
                    Text("Temperature").tag(MenuBarDisplay.temperature)
                    Text("Fan speed").tag(MenuBarDisplay.fanSpeed)
                    Text("Temperature and fan speed").tag(MenuBarDisplay.both)
                }
                sensorPicker
                    .disabled(model.settings.menuBarDisplay == .iconOnly || model.settings.menuBarDisplay == .fanSpeed)
            }

            Section("Display") {
                Picker("Temperature unit", selection: Binding(get: { model.settings.unit },
                                                              set: { model.settings.unit = $0 })) {
                    Text("Celsius (°C)").tag(TemperatureUnit.celsius)
                    Text("Fahrenheit (°F)").tag(TemperatureUnit.fahrenheit)
                }
                Picker("Update interval", selection: Binding(get: { model.settings.sampleInterval },
                                                             set: { model.settings.sampleInterval = $0 })) {
                    ForEach(intervalChoices, id: \.self) { s in
                        Text("\(s.formatted()) s").tag(s)
                    }
                }
            }

            Section("Fan control service") {
                LabeledContent("Status") { statusLabel }
                if let error = model.installError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("Reinstall") { run { await model.reinstallHelper() } }
                    Button("Remove", role: .destructive) { confirmRemove = true }
                        .disabled(model.helperStatus == .notRegistered)
                }
                .disabled(working || AppModel.localOnly || !model.hasFans)
                Text("Removing the service gives the fans back to macOS first.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Remove the fan control service?", isPresented: $confirmRemove) {
            Button("Remove", role: .destructive) { run { await model.removeHelper() } }
        } message: {
            Text("Fans go back to automatic control. You can install the service again at any time.")
        }
        .onAppear(perform: refreshLogin)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshLogin()
        }
    }

    private var intervalChoices: [Double] {
        let current = model.settings.sampleInterval
        return Self.intervalChoices.contains(current) ? Self.intervalChoices : ([current] + Self.intervalChoices).sorted()
    }

    @ViewBuilder
    private var sensorPicker: some View {
        let current = model.settings.menuBarSensor
        let choices = SensorPresentation.sourceChoices(sensors: model.snapshot?.sensors ?? [],
                                                       prefs: model.settings.sensorPrefs, current: current)
        Picker("Sensor", selection: Binding(get: { current }, set: { model.settings.menuBarSensor = $0 })) {
            Section("Groups") {
                ForEach(SensorGroup.allCases, id: \.self) { g in
                    Text(g.title).tag(SensorSourceRef.group(g))
                }
            }
            Section("Sensors") {
                ForEach(choices.sensors, id: \.id) { r in
                    Text(model.settings.sensorPrefs.displayName(r)).tag(SensorSourceRef.sensor(r.id))
                }
                if let missing = choices.missing {
                    Text("(missing) \(missing)").tag(current)
                }
            }
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch model.helperStatus {
        case .enabled: Label("Running", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .requiresApproval: Label("Waiting for approval", systemImage: "hourglass").foregroundStyle(.orange)
        case .notRegistered: Label("Not installed", systemImage: "circle").foregroundStyle(.secondary)
        case .unavailable: Label("Unavailable", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private func run(_ work: @escaping () async -> Void) {
        working = true
        Task {
            await work()
            working = false
        }
    }

    private func refreshLogin() {
        loginStatus = LoginItem.status
        launchAtLogin = LoginItem.isOn
    }

    private func setLaunchAtLogin(_ on: Bool) {
        loginError = nil
        do {
            try LoginItem.setEnabled(on)
        } catch {
            loginError = error.localizedDescription
        }
        refreshLogin()
    }
}
