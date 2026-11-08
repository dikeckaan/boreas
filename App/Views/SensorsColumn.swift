import BoreasCore
import SwiftUI

struct SensorsColumn: View {
    let model: AppModel
    @State private var expanded = false
    @State private var showHidden = false
    @State private var renaming: SensorReading?
    @State private var newName = ""

    var body: some View {
        let sensors = model.snapshot?.sensors ?? []
        let prefs = model.settings.sensorPrefs
        let groups = SensorPresentation.visible(sensors, prefs: prefs, showAll: expanded)
        let extra = SensorPresentation.visible(sensors, prefs: prefs, showAll: true).map(\.1.count).reduce(0, +)
            - SensorPresentation.visible(sensors, prefs: prefs, showAll: false).map(\.1.count).reduce(0, +)
        let hidden = sensors.filter { prefs.hidden.contains($0.id) }

        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ColumnHeader("Sensors").padding(.bottom, 6)
                if sensors.isEmpty {
                    Text("No sensor readings yet").foregroundStyle(.secondary)
                }
                ForEach(groups, id: \.0) { group, readings in
                    Text(group.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .padding(.bottom, 2)
                    ForEach(readings, id: \.id) { r in row(r, hidden: false) }
                }
                if extra > 0 || expanded {
                    Button {
                        expanded.toggle()
                    } label: {
                        HStack {
                            Text(expanded ? "Show fewer sensors" : "+\(extra) more sensors")
                            Spacer()
                            Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 10)
                }
                if !hidden.isEmpty {
                    Button {
                        showHidden.toggle()
                    } label: {
                        Text(showHidden ? "Hide hidden sensors" : "Show hidden sensors (\(hidden.count))")
                            .font(.callout)
                    }
                    .buttonStyle(.link)
                    .padding(.top, 10)
                    if showHidden {
                        ForEach(hidden, id: \.id) { r in row(r, hidden: true) }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Rename Sensor", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                if let r = renaming { model.rename(r.id, to: newName) }
            }
        } message: {
            if let r = renaming { Text("Leave empty to use “\(r.name)”.") }
        }
    }

    private func row(_ r: SensorReading, hidden: Bool) -> some View {
        let prefs = model.settings.sensorPrefs
        let starred = prefs.starred.contains(r.id)
        return HStack(spacing: 6) {
            Image(systemName: starred ? "star.fill" : "star")
                .font(.caption)
                .foregroundStyle(starred ? Color.yellow : Color.secondary.opacity(0.4))
                .frame(width: 14)
            Text(SensorPresentation.displayName(r, prefs: prefs)).lineLimit(1)
            Spacer()
            Text(SensorPresentation.format(r.celsius, unit: model.settings.unit))
                .monospacedDigit()
                .foregroundStyle(color(SensorPresentation.heat(r.celsius, group: r.group)))
        }
        .padding(.vertical, 3)
        .opacity(hidden ? 0.55 : 1)
        .contentShape(Rectangle())
        .contextMenu {
            Button(starred ? "Unstar" : "Star") { model.toggleStar(r.id) }
            Button("Rename…") {
                newName = prefs.renamed[r.id] ?? ""
                renaming = r
            }
            Button(hidden ? "Unhide" : "Hide") { model.setHidden(r.id, !hidden) }
        }
    }

    private func color(_ heat: Heat) -> Color {
        switch heat {
        case .cool: .green
        case .warm: .yellow
        case .hot: .orange
        }
    }
}
