import BoreasCore
import SwiftUI

/// What the main window's editor sheet is opened on.
struct EditorSession: Identifiable {
    let profile: Profile
    let isNew: Bool
    var id: UUID { profile.id }
}

/// Profile editor (approved mockup): name, rules and behaviour on the left, the curve on the
/// right. Edits live in a local draft and reach the model on Save, so dragging never writes
/// settings. Built-in profiles are saved under their own id; Automatic is never edited.
struct ProfileEditor: View {
    let model: AppModel
    @State private var draft: Profile
    /// False for a profile that has not been saved yet (the "+" button's new profile).
    @State private var existsInModel: Bool
    @State private var selectedRuleID: UUID?
    @State private var confirmDelete = false
    @Environment(\.dismiss) private var dismiss

    private static let ruleColors: [Color] = [.orange, .blue, .green, .pink, .purple, .teal, .yellow, .red]

    init(model: AppModel, session: EditorSession) {
        self.model = model
        _draft = State(initialValue: session.profile)
        _existsInModel = State(initialValue: !session.isNew)
        _selectedRuleID = State(initialValue: session.profile.rules.first?.id)
    }

    private var isBuiltIn: Bool { draft.builtIn != nil }
    /// Names of the other profiles, as shown (built-ins by their localized name, too).
    private var otherNames: [String] {
        model.settings.profiles.filter { $0.id != draft.id }.flatMap { [$0.name, $0.displayName] }
    }
    private var nameTaken: Bool { !isBuiltIn && ProfileNaming.isTaken(draft.name, among: otherNames) }
    private var canSave: Bool {
        isBuiltIn || (!draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !nameTaken)
    }
    private var selectedIndex: Int? { draft.rules.firstIndex { $0.id == selectedRuleID } }
    private var sensors: [SensorReading] { model.snapshot?.sensors ?? [] }

    private func color(_ index: Int) -> Color { Self.ruleColors[index % Self.ruleColors.count] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                left
                    .frame(width: 300)
                Divider()
                right
            }
            Divider()
            footer
        }
        .frame(width: 800, height: 500)
        .confirmationDialog("Delete “\(draft.name)”?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                model.deleteProfile(draft.id)
                dismiss()
            }
        } message: {
            Text("This cannot be undone.")
        }
    }

    // MARK: - Left

    private var left: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if isBuiltIn {
                    Text(draft.displayName).font(.title3.weight(.semibold))
                } else {
                    TextField("Name", text: $draft.name)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                    if nameTaken {
                        Label("Another profile already has this name.", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                ColumnHeader("Rules")
                VStack(spacing: 6) {
                    ForEach(Array(draft.rules.enumerated()), id: \.element.id) { i, rule in
                        ruleRow(index: i, rule: rule)
                    }
                }
                Button {
                    addRule()
                } label: {
                    Label("Add sensor rule", systemImage: "plus")
                }
                .buttonStyle(.link)

                ColumnHeader("Behavior")
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Smooth transitions", isOn: $draft.behavior.smoothing)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Delay response")
                            Spacer()
                            Text(SensorPresentation.format(draft.behavior.hysteresisC, unit: .celsius))
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $draft.behavior.hysteresisC, in: 0...10, step: 1)
                    }
                    Toggle("Release to Apple below the curve", isOn: $draft.behavior.releaseToAppleBelowMin)
                }
            }
            .padding(16)
        }
    }

    private func ruleRow(index: Int, rule: Rule) -> some View {
        let selected = rule.id == selectedRuleID
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3).fill(color(index)).frame(width: 12, height: 12)
            Picker("Sensor", selection: Binding(
                get: { rule.source },
                set: { new in draft.rules[index].source = new })) {
                Section("Groups") {
                    ForEach(SensorGroup.allCases, id: \.self) { g in
                        Text(g.title).tag(SensorSourceRef.group(g))
                    }
                }
                let choices = SensorPresentation.sourceChoices(
                    sensors: sensors, prefs: model.settings.sensorPrefs, current: rule.source)
                Section("Sensors") {
                    ForEach(choices.sensors, id: \.id) { r in
                        Text(model.settings.sensorPrefs.displayName(r)).tag(SensorSourceRef.sensor(r.id))
                    }
                    if let missing = choices.missing {
                        Text("(missing) \(missing)").tag(rule.source)
                    }
                }
            }
            .labelsHidden()
            Button {
                removeRule(rule.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(draft.rules.count <= 1)
            .help("Remove rule")
            .accessibilityLabel("Remove rule")
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(selected ? Color.accentColor : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { selectedRuleID = rule.id }
    }

    private func addRule() {
        let base = selectedIndex.map { draft.rules[$0].curve }
            ?? BuiltInProfiles.all()[1].rules[0].curve
        let used = Set(draft.rules.map(\.source))
        let source = SensorGroup.allCases.map(SensorSourceRef.group).first { !used.contains($0) } ?? .group(.cpu)
        let rule = Rule(source: source, curve: base)
        draft.rules.append(rule)
        selectedRuleID = rule.id
    }

    private func removeRule(_ id: UUID) {
        guard draft.rules.count > 1, let i = draft.rules.firstIndex(where: { $0.id == id }) else { return }
        draft.rules.remove(at: i)
        if selectedRuleID == id { selectedRuleID = draft.rules[Swift.min(i, draft.rules.count - 1)].id }
    }

    // MARK: - Right

    private var right: some View {
        VStack(alignment: .leading, spacing: 8) {
            ColumnHeader("Curve")
            if let i = selectedIndex {
                let rule = draft.rules[i]
                CurveChart(
                    series: draft.rules.enumerated().map { .init(id: $1.id, curve: $1.curve, color: color($0)) },
                    selectedID: rule.id,
                    currentCelsius: rule.source.temperature(in: sensors),
                    fanRange: model.fans.first.map { $0.min...Swift.max($0.min, $0.max) },
                    unit: model.settings.unit,
                    onCommit: { id, curve in
                        if let j = draft.rules.firstIndex(where: { $0.id == id }) { draft.rules[j].curve = curve }
                    })
                Text("Drag points to shape the curve. Double-click empty space to add a point, right-click a point to remove it.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("No rule selected").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if existsInModel && !isBuiltIn {
                Button("Delete", role: .destructive) { confirmDelete = true }
            }
            Spacer()
            Button("Duplicate") { duplicate() }
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save") {
                var p = draft
                p.name = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
                model.saveProfile(p)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canSave)
        }
        .padding(12)
    }

    /// Opens a copy of what is on screen as a new, unsaved user profile. Nothing is written until Save.
    private func duplicate() {
        let base = String(localized: "\(draft.displayName) copy")
        var name = base
        var n = 2
        while ProfileNaming.isTaken(name, among: otherNames + [draft.name]) {
            name = "\(base) \(n)"
            n += 1
        }
        let copy = CurveEditing.duplicate(draft, name: name)
        draft = copy
        existsInModel = false
        selectedRuleID = copy.rules.first?.id
    }
}
