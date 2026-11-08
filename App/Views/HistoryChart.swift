import BoreasCore
import Charts
import SwiftUI

/// Collapsible temperature history: CPU, GPU, starred sensors (left axis) and fan speed
/// (dashed, right axis).
struct HistoryChart: View {
    let model: AppModel
    @State private var range: Range = .tenMinutes

    enum Range: CaseIterable, Identifiable {
        case oneMinute, tenMinutes, oneHour
        var id: Self { self }
        var seconds: TimeInterval {
            switch self { case .oneMinute: 60; case .tenMinutes: 600; case .oneHour: 3600 }
        }
        var label: LocalizedStringKey {
            switch self { case .oneMinute: "1 min"; case .tenMinutes: "10 min"; case .oneHour: "1 hr" }
        }
    }

    private struct Point: Identifiable {
        let id: String
        let date: Date
        /// Series key (`cpu`, `fanN`, sensor id): one line each.
        let series: String
        /// Display name for the legend and colour.
        let label: String
        let y: Double
        let dashed: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    model.settings.historyCollapsed.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.settings.historyCollapsed ? "chevron.right" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .frame(width: 10)
                        ColumnHeader("History")
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(model.settings.historyCollapsed ? Text("Show history") : Text("Hide history"))
                Spacer()
                if !model.settings.historyCollapsed {
                    Picker("Range", selection: $range) {
                        ForEach(Range.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            if !model.settings.historyCollapsed {
                chart
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var chart: some View {
        let now = Date()
        let samples = SensorPresentation.thin(model.history.samples(since: now.addingTimeInterval(-range.seconds)),
                                              maxCount: 300)
        let unit = model.settings.unit
        let prefs = model.settings.sensorPrefs
        let sensors = model.snapshot?.sensors ?? []
        let fanMax = Swift.max(1, model.fans.map(\.max).max() ?? 1)

        // Series in a stable order: cpu, gpu, fans, starred sensors. Series are keyed by `cpu`,
        // `fanN` or the sensor id, so two sensors with the same name stay separate lines.
        let starredIDs = prefs.starred.map(\.rawValue).sorted()
        let names: [String: String] = {
            var n: [String: String] = ["cpu": String(localized: "CPU"), "gpu": String(localized: "GPU")]
            for fan in model.fans { n["fan\(fan.index)"] = Format.fanName(fan.index, count: model.fans.count) }
            for r in sensors where prefs.starred.contains(r.id) { n[r.id.rawValue] = prefs.displayName(r) }
            return n
        }()
        let keys = ["cpu", "gpu"] + model.fans.map { "fan\($0.index)" } + starredIDs
        let present = keys.filter { k in samples.contains { $0.values[k] != nil } }
        let fanKeys = Set(model.fans.map { "fan\($0.index)" })
        let isFan: (String) -> Bool = { fanKeys.contains($0) }

        // Legend labels: the display name; a shared name gets the key appended so the legend and
        // colours stay distinguishable.
        let nameCounts = Dictionary(present.map { (names[$0] ?? $0, 1) }, uniquingKeysWith: +)
        let labels: [String: String] = Dictionary(uniqueKeysWithValues: present.map { k in
            let name = names[k] ?? k
            return (k, (nameCounts[name] ?? 1) > 1 ? "\(name) (\(k))" : name)
        })

        // The temperature axis grows with the data: 0 ... max(100, hottest reading + 5), display unit.
        let observedMax = samples.flatMap { s in
            present.filter { !isFan($0) }.compactMap { s.values[$0] }
        }.map { SensorPresentation.value($0, unit: unit) }.max() ?? 0
        let tempMax = Swift.max(SensorPresentation.value(100, unit: unit), observedMax + 5)

        let points: [Point] = samples.flatMap { s in
            present.compactMap { k -> Point? in
                guard let v = s.values[k] else { return nil }
                let y = isFan(k) ? v / fanMax * tempMax : SensorPresentation.value(v, unit: unit)
                return Point(id: "\(k)@\(s.date.timeIntervalSince1970)", date: s.date, series: k,
                             label: labels[k] ?? k, y: y, dashed: isFan(k))
            }
        }
        let palette: [Color] = [.yellow, .green, .blue, .indigo, .pink, .orange, .teal, .purple, .mint]
        let colorDomain = present.map { labels[$0] ?? $0 }
        let colorRange = present.enumerated().map { palette[$0.offset % palette.count] }

        Chart(points) { p in
            LineMark(x: .value("Time", p.date), y: .value("Value", p.y), series: .value("Series", p.series))
                .foregroundStyle(by: .value("Name", p.label))
                .lineStyle(StrokeStyle(lineWidth: 1.6, dash: p.dashed ? [4, 3] : []))
                .interpolationMethod(.monotone)
        }
        .chartXScale(domain: now.addingTimeInterval(-range.seconds)...now)
        .chartYScale(domain: 0...tempMax)
        .chartForegroundStyleScale(domain: colorDomain, range: colorRange)
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(verbatim: "\(Int(v.rounded()))°") }
                }
            }
            if model.hasFans {
                AxisMarks(position: .trailing, values: [0, tempMax / 2, tempMax]) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text((v / tempMax * fanMax).formatted(.number.precision(.fractionLength(0))))
                        }
                    }
                }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading)
        .frame(height: 130)
        .overlay {
            if present.isEmpty {
                Text("No readings yet").font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
