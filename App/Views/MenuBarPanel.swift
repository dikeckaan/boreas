import AppKit
import BoreasCore
import SwiftUI

// MARK: - Menu bar label

struct MenuBarLabel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 4) {
            Image("MenuBarIcon")
                .accessibilityLabel("Boreas")
            if let text = model.menuBarText {
                Text(text).monospacedDigit()
            }
        }
        // First launch (spec §6.1): the window opens by itself, once per run, when onboarding is needed.
        .onChange(of: model.needsOnboarding, initial: true) { _, needed in
            guard needed, !model.welcomeShown else { return }
            model.welcomeShown = true
            openWindow(id: "main")
            NSApp.activate()
        }
    }
}

extension AppModel {
    /// Text next to the menu bar icon, per `menuBarDisplay`; nil for icon only or no data yet.
    var menuBarText: String? {
        guard let snapshot else { return nil }
        let temperature = settings.menuBarSensor.temperature(in: snapshot.sensors)
            .map { SensorPresentation.format($0, unit: settings.unit, compact: true) }
        let rpm = snapshot.fans.map(\.actual).filter(\.isFinite).max().map(Format.rpm)
        let parts: [String?]
        switch settings.menuBarDisplay {
        case .iconOnly: parts = []
        case .temperature: parts = [temperature]
        case .fanSpeed: parts = [rpm]
        case .both: parts = [temperature, rpm]
        }
        let text = parts.compactMap { $0 }.joined(separator: " · ")
        return text.isEmpty ? nil : text
    }
}

// MARK: - Panel

/// The window that opens from the menu bar icon (approved mockup, left part).
struct MenuBarPanel: View {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.helperUnresponsive {
                Label("Fan control helper isn't responding. Use Settings › Reinstall Helper, or restart your Mac.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            if model.hasFans {
                SectionHeader("Profile")
                profileSection
                SectionHeader("Fans")
                ForEach(model.fans, id: \.index) { fan in
                    FanRow(model: model, fan: fan)
                }
                if model.snapshot?.ceilingTripped == true, model.snapshot?.ceilingBlind != true {
                    Label("Safety: full speed", systemImage: "flame.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
            } else if model.fanCount == 0 {
                SectionHeader("Fans")
                PanelRow { Text("This Mac has no fans").foregroundStyle(.secondary) }
            }

            SectionHeader("Hottest 3")
            let hottest = model.settings.sensorPrefs.hottest(model.snapshot?.sensors ?? [], count: 3)
            if hottest.isEmpty {
                PanelRow { Text("No sensor readings yet").foregroundStyle(.secondary) }
            }
            ForEach(hottest, id: \.id) { r in
                PanelRow {
                    Text(model.settings.sensorPrefs.displayName(r)).lineLimit(1)
                    Spacer()
                    Text(SensorPresentation.format(r.celsius, unit: model.settings.unit, compact: true)).monospacedDigit()
                }
            }

            Divider().padding(.top, 6)
            VStack(alignment: .leading, spacing: 2) {
                PanelButton("Open Window…") { showMainWindow() }
                    .foregroundStyle(Color.accentColor)
                PanelButton("Settings…") { showSettings() }
                PanelButton("Quit Boreas") { NSApp.terminate(nil) }
            }
            .padding(.vertical, 4)
        }
        .frame(width: 280)
    }

    @ViewBuilder
    private var profileSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowLayout(spacing: 4) {
                ForEach(model.settings.profiles) { p in
                    ProfilePill(title: p.displayName, selected: p.id == model.settings.activeProfileID) {
                        model.selectProfile(p.id)
                    }
                }
            }
            .disabled(!model.canControlFans)
            if !model.canControlFans {
                Button {
                    showMainWindow()
                } label: {
                    if model.helperStatus == .unavailable {
                        Label("Fan control unavailable", systemImage: "exclamationmark.circle")
                    } else {
                        Label("Set up fan control…", systemImage: "exclamationmark.circle")
                    }
                }
                .buttonStyle(.link)
                .font(.callout)
            } else if let error = model.helperProblem {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private func showSettings() {
        openWindow(id: "settings")
        NSApp.activate()
        dismiss()
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate()
        dismiss()
    }
}

private struct FanRow: View {
    let model: AppModel
    let fan: FanInfo

    var body: some View {
        PanelRow {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(Format.fanName(fan.index, count: model.fans.count))
                    if case .fixed = model.mode(of: fan.index) {
                        Text("Fixed")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                if model.snapshot?.commands[fan.index] == "unverified" {
                    Label("Couldn't confirm Automatic", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            Text(Format.rpmWithUnit(fan.actual)).monospacedDigit()
        }
    }
}

// MARK: - Building blocks

private struct SectionHeader: View {
    let title: LocalizedStringResource
    init(_ title: LocalizedStringResource) { self.title = title }

    var body: some View {
        // Upper-cased here, by the app language's rules, rather than with `.textCase`.
        Text(verbatim: AppLanguage.uppercased(title))
            .font(.caption2.weight(.medium))
            .kerning(0.6)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }
}

private struct PanelRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack { content }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
    }
}

private struct PanelButton: View {
    let title: LocalizedStringKey
    let action: () -> Void
    @State private var hovering = false

    init(_ title: LocalizedStringKey, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(hovering ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                            in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        .onHover { hovering = $0 }
    }
}

private struct ProfilePill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                            in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lays children out left to right, wrapping onto new lines.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(Swift.max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (i, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row()
            }
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = Swift.max(row.height, size.height)
            row.indices.append(i)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Formatting

extension Profile {
    /// Built-in names are localized keys; user profiles show their own name.
    var displayName: String {
        switch builtIn {
        case .automatic: String(localized: "Automatic")
        case .silent: String(localized: "Silent")
        case .performance: String(localized: "Performance")
        case nil: name
        }
    }
}

/// Number formatting shared by the menu bar and the main window. Temperatures go through
/// `SensorPresentation.format`.
enum Format {
    static func rpm(_ value: Double) -> String {
        guard value.isFinite else { return "–" }
        return Int(value.rounded()).formatted()
    }

    static func rpmWithUnit(_ value: Double) -> String {
        String(localized: "\(rpm(value)) rpm")
    }

    static func fanName(_ index: Int, count: Int) -> String {
        count == 1 ? String(localized: "Fan") : String(localized: "Fan \(index + 1)")
    }
}
