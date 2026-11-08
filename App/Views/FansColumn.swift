import BoreasCore
import SwiftUI

struct FansColumn: View {
    let model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ColumnHeader("Fans").padding(.bottom, 8)
                if model.snapshot?.ceilingTripped == true {
                    Label("Safety: full speed", systemImage: "flame.fill")
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.15), in: Capsule())
                        .padding(.bottom, 8)
                }
                if model.fans.isEmpty {
                    if model.fanCount == 0 {
                        Text("This Mac has no fans").foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(model.fans, id: \.index) { fan in
                        FanSection(model: model, fan: fan)
                        Divider().padding(.vertical, 8)
                    }
                    Text("Set each fan to Automatic, a fixed speed, or the active profile.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FanSection: View {
    let model: AppModel
    let fan: FanInfo

    private enum Choice: Hashable { case auto, fixed, profile }

    private var mode: FanMode { model.mode(of: fan.index) }

    private var choice: Choice {
        switch mode {
        case .auto: .auto
        case .fixed: .fixed
        case .profile: .profile
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(Format.fanName(fan.index, count: model.fans.count))
                    Text("\(Format.rpm(fan.min)) – \(Format.rpm(fan.max)) rpm")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(Format.rpmWithUnit(fan.actual)).monospacedDigit()
            }
            HStack {
                Picker("Mode", selection: Binding(get: { choice }, set: select)) {
                    Text("Automatic").tag(Choice.auto)
                    Text("Fixed speed").tag(Choice.fixed)
                    Text("Profile").tag(Choice.profile)
                        .disabled(model.settings.activeProfileID == BuiltInProfiles.automaticID)
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!model.canControlFans)
                if choice == .profile, let p = model.settings.activeProfile {
                    Text(p.displayName).font(.caption).foregroundStyle(.secondary)
                }
            }
            if case .fixed(let rpm) = mode {
                FixedSpeedControl(fan: fan, rpm: rpm, enabled: model.canControlFans) {
                    model.setFanMode(fan.index, .fixed(rpm: $0))
                }
            }
            if model.snapshot?.commands[fan.index] == "unverified" {
                Label("Couldn't confirm Automatic", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func select(_ c: Choice) {
        switch c {
        case .auto: model.setFanMode(fan.index, .auto)
        case .profile: model.setFanMode(fan.index, .profile)
        case .fixed:
            let start = fan.actual.isFinite ? fan.actual : fan.min
            model.setFanMode(fan.index, .fixed(rpm: Swift.min(Swift.max(start, fan.min), fan.max)))
        }
    }
}

/// Slider and number field, both clamped to the fan's min…max. The value is sent when the drag
/// ends or the field is submitted, not on every step.
private struct FixedSpeedControl: View {
    let fan: FanInfo
    let rpm: Double
    let enabled: Bool
    let commit: (Double) -> Void

    @State private var draft: Double?
    @State private var text = ""
    @FocusState private var editing: Bool

    private var value: Double { draft ?? rpm }
    private var range: ClosedRange<Double> { fan.min...Swift.max(fan.min, fan.max) }

    var body: some View {
        HStack(spacing: 8) {
            Slider(value: Binding(get: { value }, set: { draft = $0 }), in: range, step: 10) { dragging in
                if !dragging, let d = draft {
                    commit(clamped(d))
                    draft = nil
                }
            }
            .disabled(!enabled)
            TextField("rpm", text: $text)
                .focused($editing)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 64)
                .disabled(!enabled)
                .onSubmit(submit)
                .onChange(of: editing) { _, now in if !now { submit() } }
            Text("rpm").font(.caption).foregroundStyle(.secondary)
        }
        .onAppear { text = String(Int(rpm.rounded())) }
        .onChange(of: rpm) { _, new in if !editing { text = String(Int(new.rounded())) } }
        .onChange(of: draft) { _, new in if let new, !editing { text = String(Int(new.rounded())) } }
    }

    private func clamped(_ v: Double) -> Double { Swift.min(Swift.max(v, range.lowerBound), range.upperBound) }

    private func submit() {
        guard let parsed = Double(text.trimmingCharacters(in: .whitespaces)) else {
            text = String(Int(rpm.rounded()))
            return
        }
        let v = clamped(parsed)
        text = String(Int(v.rounded()))
        if v != rpm { commit(v) }
    }
}
