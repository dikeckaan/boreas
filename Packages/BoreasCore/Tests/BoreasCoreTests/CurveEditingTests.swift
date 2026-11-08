import Testing
import Foundation
@testable import BoreasCore

private func curve(_ n: Int) -> Curve {
    Curve(points: (0..<n).map { .init(celsius: 30 + Double($0) * 10, fraction: Double($0) / Double(n)) })
}

@Test func moveKeepsOrder() {
    let c = CurveEditing.move(silent, index: 0, to: .init(celsius: 99, fraction: 0))
    #expect(c.points[0].celsius == 94)
}
@Test func moveKeepsOrderFromBelow() {
    let c = CurveEditing.move(silent, index: 1, to: .init(celsius: 10, fraction: 1))
    #expect(c.points[1].celsius == 56)
}
@Test func moveClamps() {
    #expect(CurveEditing.move(silent, index: 1, to: .init(celsius: 200, fraction: 2)).points[1] == .init(celsius: 110, fraction: 1))
    #expect(CurveEditing.move(silent, index: 0, to: .init(celsius: -5, fraction: -1)).points[0] == .init(celsius: 20, fraction: 0))
}
@Test func moveBadIndexIsNoOp() {
    #expect(CurveEditing.move(silent, index: 5, to: .init(celsius: 60, fraction: 0)) == silent)
    #expect(CurveEditing.move(silent, index: -1, to: .init(celsius: 60, fraction: 0)) == silent)
}
@Test func insertOnCurve() {
    let c = CurveEditing.insert(silent, at: 75)
    #expect(c.points.count == 3)
    #expect(c.points[1] == .init(celsius: 75, fraction: 0.5))
}
@Test func insertOutsideRangeKeepsOrder() {
    let c = CurveEditing.insert(silent, at: 30)
    #expect(c.points.map(\.celsius) == [30, 55, 95])
    #expect(c.points[0].fraction == 0)
}
@Test func insertTooCloseIsNoOp() {
    #expect(CurveEditing.insert(silent, at: 55.5) == silent)
}
@Test func maxEightMinTwo() {
    let eight = curve(8)
    #expect(CurveEditing.insert(eight, at: 35) == eight)
    #expect(CurveEditing.insert(curve(7), at: 35).points.count == 8)
    #expect(CurveEditing.remove(silent, index: 0) == silent)
    #expect(CurveEditing.remove(curve(3), index: 1).points.count == 2)
    #expect(CurveEditing.remove(curve(3), index: 9).points.count == 3)
}
@Test func duplicateBuiltIn() {
    let src = BuiltInProfiles.all()[1]
    let d = CurveEditing.duplicate(src, name: "Sessiz kopya")
    #expect(d.builtIn == nil)
    #expect(d.id != BuiltInProfiles.silentID)
    #expect(d.name == "Sessiz kopya")
    #expect(d.rules.count == 1)
    #expect(d.rules[0].id != src.rules[0].id)
    #expect(d.rules[0].curve == src.rules[0].curve)
    #expect(d.behavior == src.behavior)
}
