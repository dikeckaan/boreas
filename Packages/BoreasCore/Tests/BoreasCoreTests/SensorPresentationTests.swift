import Foundation
import Testing
@testable import BoreasCore

private func r(_ id: String, _ c: Double, _ g: SensorGroup, name: String? = nil, featured: Bool = false,
               suspect: Bool = false) -> SensorReading {
    SensorReading(id: SensorID(id), rawName: id, name: name ?? id, group: g, celsius: c,
                  featured: featured, safety: false, suspect: suspect)
}

@Test func heatThresholds() {
    #expect(SensorPresentation.heat(60, group: .cpu) == .cool)
    #expect(SensorPresentation.heat(75, group: .cpu) == .warm)
    #expect(SensorPresentation.heat(90, group: .cpu) == .hot)
    #expect(SensorPresentation.heat(50, group: .storage) == .warm)
    // Boundaries: warm and hot start at the threshold itself.
    #expect(SensorPresentation.heat(70, group: .gpu) == .warm)
    #expect(SensorPresentation.heat(85, group: .gpu) == .hot)
    #expect(SensorPresentation.heat(65, group: .storage) == .hot)
    #expect(SensorPresentation.heat(39.9, group: .battery) == .cool)
    #expect(SensorPresentation.heat(50, group: .battery) == .hot)
    #expect(SensorPresentation.heat(60, group: .memory) == .warm)
    #expect(SensorPresentation.heat(80, group: .other) == .hot)
}

@Test func starredFirstHiddenGoneCollapsedShowsFeatured() {
    let a = r("a", 50, .cpu, featured: true)
    let b = r("b", 52, .cpu)
    let c = r("c", 54, .cpu, featured: true)
    let d = r("d", 40, .gpu)
    let hidden = r("h", 41, .gpu, featured: true)
    let sus = r("s", 130, .cpu, featured: true, suspect: true)
    let prefs = SensorPrefs(starred: [SensorID("b")], renamed: [:], hidden: [SensorID("h")])
    let readings = [a, b, c, d, hidden, sus]

    let collapsed = SensorPresentation.visible(readings, prefs: prefs, showAll: false)
    #expect(collapsed.map(\.0) == [.cpu])
    #expect(collapsed[0].1.map(\.id.rawValue) == ["b", "a", "c"])   // starred first; no hidden, no suspect, no plain gpu

    let all = SensorPresentation.visible(readings, prefs: prefs, showAll: true)
    #expect(all.map(\.0) == [.cpu, .gpu])
    #expect(all[0].1.map(\.id.rawValue) == ["b", "a", "c", "s"])
    #expect(all[1].1.map(\.id.rawValue) == ["d"])                   // hidden stays gone
}

@Test func groupsFollowDeclaredOrderAndEmptyOnesVanish() {
    let out = SensorPresentation.visible([r("x", 30, .battery), r("y", 30, .cpu), r("z", 30, .storage)],
                                         prefs: SensorPrefs(), showAll: true)
    #expect(out.map(\.0) == [.cpu, .storage, .battery])
}

@Test func renamedWins() {
    let s = r("hid:x", 50, .cpu, name: "CPU die")
    #expect(SensorPresentation.displayName(s, prefs: .init(starred: [], renamed: [s.id: "Ana kart"], hidden: [])) == "Ana kart")
    #expect(SensorPresentation.displayName(s, prefs: SensorPrefs()) == "CPU die")
}

@Test func fahrenheit() {
    #expect(SensorPresentation.format(100, unit: .fahrenheit) == "212°F")
    #expect(SensorPresentation.format(62.4, unit: .celsius) == "62°C")
    #expect(SensorPresentation.format(.nan, unit: .celsius) == "–")
}

@Test func convertsToDisplayUnit() {
    #expect(SensorPresentation.value(100, unit: .fahrenheit) == 212)
    #expect(SensorPresentation.value(37, unit: .celsius) == 37)
}

@Test func thinKeepsEndsAndCapsCount() {
    let a = Array(0..<3600)
    let t = SensorPresentation.thin(a, maxCount: 300)
    #expect(t.count <= 300)
    #expect(t.first == 0 && t.last == 3599)
    #expect(t == t.sorted())
    #expect(SensorPresentation.thin([1, 2, 3], maxCount: 300) == [1, 2, 3])
    #expect(SensorPresentation.thin(a, maxCount: 1) == [3599])
}

@Test func applicationsFolderDetection() {
    #expect(AppInstallLocation.isInApplications(URL(fileURLWithPath: "/Applications/Boreas.app")))
    #expect(AppInstallLocation.isInApplications(URL(fileURLWithPath: "/Applications/Utilities/Boreas.app")))
    #expect(!AppInstallLocation.isInApplications(URL(fileURLWithPath: "/Volumes/X/build/Boreas.app")))
    #expect(!AppInstallLocation.isInApplications(URL(fileURLWithPath: "/Users/me/Downloads/Boreas.app")))
    #expect(!AppInstallLocation.isInApplications(URL(fileURLWithPath: "/ApplicationsX/Boreas.app")))
}
