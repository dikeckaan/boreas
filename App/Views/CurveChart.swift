import AppKit
import BoreasCore
import Charts
import SwiftUI

/// The profile editor's curve plot: x is temperature (20–110 °C), y the fan's range (rpm of the
/// first fan, or percent). The selected rule's points can be dragged; double-click on empty space
/// adds a point, right-click on a point removes it. While a point is being dragged only this
/// view's state changes; the edited curve goes to `onCommit` once, when the drag ends.
struct CurveChart: View {
    struct Series: Identifiable {
        let id: UUID
        let curve: Curve
        let color: Color
    }

    let series: [Series]
    let selectedID: UUID
    /// Current temperature of the selected rule's source (dashed vertical line).
    let currentCelsius: Double?
    /// First fan's [min, max] rpm; nil without fans (the axis then shows percent).
    let fanRange: ClosedRange<Double>?
    let unit: TemperatureUnit
    let onCommit: (UUID, Curve) -> Void

    @State private var drag: DragState?

    private struct DragState {
        var index: Int
        var curve: Curve
    }

    private static let xDomain = CurveEditing.minCelsius...CurveEditing.maxCelsius
    private static let grabRadius: CGFloat = 14

    private func shown(_ s: Series) -> Curve {
        s.id == selectedID ? (drag?.curve ?? s.curve) : s.curve
    }

    private var selected: Series? { series.first { $0.id == selectedID } }

    /// The curve extended flat to both ends of the axis.
    private func line(_ c: Curve) -> [CurvePoint] {
        guard let first = c.points.first, let last = c.points.last else { return [] }
        var pts = c.points
        if first.celsius > Self.xDomain.lowerBound {
            pts.insert(CurvePoint(celsius: Self.xDomain.lowerBound, fraction: first.fraction), at: 0)
        }
        if last.celsius < Self.xDomain.upperBound {
            pts.append(CurvePoint(celsius: Self.xDomain.upperBound, fraction: last.fraction))
        }
        return pts
    }

    private func fanLabel(_ fraction: Double) -> String {
        if let r = fanRange {
            return Format.rpmWithUnit(r.lowerBound + fraction * (r.upperBound - r.lowerBound))
        }
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    var body: some View {
        Chart {
            ForEach(series) { s in
                let isSelected = s.id == selectedID
                ForEach(Array(line(shown(s)).enumerated()), id: \.offset) { _, p in
                    LineMark(x: .value("Temperature", p.celsius), y: .value("Fan", p.fraction),
                             series: .value("Rule", s.id.uuidString))
                        .foregroundStyle(s.color.opacity(isSelected ? 1 : 0.3))
                        .lineStyle(StrokeStyle(lineWidth: isSelected ? 2.4 : 1.4))
                }
            }
            if let currentCelsius, Self.xDomain.contains(currentCelsius) {
                RuleMark(x: .value("Now", currentCelsius))
                    .foregroundStyle(.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text(SensorPresentation.format(currentCelsius, unit: unit))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
            }
            if let selected {
                ForEach(Array(shown(selected).points.enumerated()), id: \.offset) { i, p in
                    PointMark(x: .value("Temperature", p.celsius), y: .value("Fan", p.fraction))
                        .symbolSize(drag?.index == i ? 150 : 80)
                        .foregroundStyle(selected.color)
                        .annotation(position: .top, spacing: 4) {
                            if drag?.index == i {
                                Text(verbatim: "\(SensorPresentation.format(p.celsius, unit: unit)), \(fanLabel(p.fraction))")
                                    .font(.caption2.monospacedDigit())
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                            }
                        }
                }
            }
        }
        .chartXScale(domain: Self.xDomain)
        .chartYScale(domain: 0...1)
        .chartXAxis {
            AxisMarks(values: Array(stride(from: 20.0, through: 110.0, by: 10.0))) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(SensorPresentation.format(v, unit: unit)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: [0.0, 0.25, 0.5, 0.75, 1.0]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let v = value.as(Double.self) { Text(fanLabel(v)) }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plot = proxy.plotFrame.map { geo[$0] } ?? .zero
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in dragChanged(v, proxy: proxy, plot: plot) }
                        .onEnded { _ in dragEnded() })
                    .simultaneousGesture(SpatialTapGesture(count: 2).onEnded { v in
                        addPoint(at: v.location, proxy: proxy, plot: plot)
                    })
                    .overlay {
                        RightClickCatcher { location in
                            removePoint(at: location, proxy: proxy, plot: plot)
                        }
                    }
            }
        }
        .accessibilityLabel("Fan curve")
    }

    // MARK: - Interaction

    private func dataPoint(at location: CGPoint, proxy: ChartProxy, plot: CGRect) -> CurvePoint? {
        guard let t = proxy.value(atX: location.x - plot.minX, as: Double.self),
              let f = proxy.value(atY: location.y - plot.minY, as: Double.self) else { return nil }
        return CurvePoint(celsius: t, fraction: f)
    }

    /// Index of the selected curve's point within grabbing distance of `location`.
    private func pointIndex(near location: CGPoint, curve: Curve, proxy: ChartProxy, plot: CGRect) -> Int? {
        var best: (Int, CGFloat)?
        for (i, p) in curve.points.enumerated() {
            guard let x = proxy.position(forX: p.celsius), let y = proxy.position(forY: p.fraction) else { continue }
            let d = hypot(plot.minX + x - location.x, plot.minY + y - location.y)
            if d <= Self.grabRadius, d < (best?.1 ?? .infinity) { best = (i, d) }
        }
        return best?.0
    }

    private func dragChanged(_ v: DragGesture.Value, proxy: ChartProxy, plot: CGRect) {
        guard let selected else { return }
        if drag == nil {
            guard let i = pointIndex(near: v.startLocation, curve: selected.curve, proxy: proxy, plot: plot)
            else { return }
            drag = DragState(index: i, curve: selected.curve)
        }
        guard let d = drag, let p = dataPoint(at: v.location, proxy: proxy, plot: plot) else { return }
        // Edits are applied to the curve as it was when the drag began.
        drag?.curve = CurveEditing.move(selected.curve, index: d.index, to: p)
    }

    private func dragEnded() {
        guard let d = drag else { return }
        onCommit(selectedID, d.curve)
        drag = nil
    }

    private func addPoint(at location: CGPoint, proxy: ChartProxy, plot: CGRect) {
        guard let selected, drag == nil,
              pointIndex(near: location, curve: selected.curve, proxy: proxy, plot: plot) == nil,
              let p = dataPoint(at: location, proxy: proxy, plot: plot) else { return }
        let edited = CurveEditing.insert(selected.curve, at: p.celsius)
        if edited != selected.curve { onCommit(selectedID, edited) }
    }

    private func removePoint(at location: CGPoint, proxy: ChartProxy, plot: CGRect) {
        guard let selected, drag == nil,
              let i = pointIndex(near: location, curve: selected.curve, proxy: proxy, plot: plot) else { return }
        let edited = CurveEditing.remove(selected.curve, index: i)
        if edited != selected.curve { onCommit(selectedID, edited) }
    }
}

/// Reports right-clicks (and control-clicks) in its area. It only takes part in hit testing for
/// those events, so ordinary clicks and drags pass through to the chart gestures.
private struct RightClickCatcher: NSViewRepresentable {
    let onRightClick: (CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.handler = onRightClick
        return v
    }

    func updateNSView(_ view: CatcherView, context: Context) {
        view.handler = onRightClick
    }

    final class CatcherView: NSView {
        var handler: ((CGPoint) -> Void)?
        override var isFlipped: Bool { true }

        private func isSecondaryClick(_ e: NSEvent) -> Bool {
            e.type == .rightMouseDown || (e.type == .leftMouseDown && e.modifierFlags.contains(.control))
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let e = NSApp.currentEvent, isSecondaryClick(e) else { return nil }
            return super.hitTest(point)
        }

        override func rightMouseDown(with event: NSEvent) {
            handler?(convert(event.locationInWindow, from: nil))
        }

        override func mouseDown(with event: NSEvent) {
            if isSecondaryClick(event) { rightMouseDown(with: event) } else { super.mouseDown(with: event) }
        }
    }
}
