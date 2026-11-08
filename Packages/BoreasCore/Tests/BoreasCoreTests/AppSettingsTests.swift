import Foundation
import Testing
@testable import BoreasCore

// MARK: - selectProfile (spec §5.3)

@Test func selectingAutomaticSetsEveryFanToAuto() {
    var s = AppSettings.defaults
    s.activeProfileID = BuiltInProfiles.silentID
    s.fanModes = [0: .profile, 1: .fixed(rpm: 2000)]
    s.selectProfile(BuiltInProfiles.automaticID, fans: [0, 1, 2])
    #expect(s.activeProfileID == BuiltInProfiles.automaticID)
    #expect(s.fanModes == [0: .auto, 1: .auto, 2: .auto])
}

@Test func selectingProfileMovesAutoFansAndKeepsFixed() {
    var s = AppSettings.defaults
    s.fanModes = [0: .auto, 1: .fixed(rpm: 2000)]
    s.selectProfile(BuiltInProfiles.silentID, fans: [0, 1, 2])
    #expect(s.activeProfileID == BuiltInProfiles.silentID)
    // Fan 2 was missing from fanModes, so it counted as auto.
    #expect(s.fanModes == [0: .profile, 1: .fixed(rpm: 2000), 2: .profile])
}

@Test func switchingBetweenProfilesKeepsProfileFans() {
    var s = AppSettings.defaults
    s.selectProfile(BuiltInProfiles.silentID, fans: [0])
    s.selectProfile(BuiltInProfiles.performanceID, fans: [0])
    #expect(s.activeProfileID == BuiltInProfiles.performanceID)
    #expect(s.fanModes == [0: .profile])
}

@Test func selectingUnknownProfileIsIgnored() {
    var s = AppSettings.defaults
    s.selectProfile(UUID(), fans: [0])
    #expect(s == .defaults)
}

@Test func selectProfileAlsoCoversFansOnlyInModes() {
    // Fans not reported right now (e.g. before the first snapshot) still follow the rule.
    var s = AppSettings.defaults
    s.fanModes = [3: .auto]
    s.selectProfile(BuiltInProfiles.silentID, fans: [])
    #expect(s.fanModes == [3: .profile])
}

// MARK: - Helper configuration

@Test func configurationForAutomaticHasNoProfile() {
    var s = AppSettings.defaults
    s.fanModes = [0: .fixed(rpm: 1500)]
    #expect(s.helperConfiguration == HelperConfiguration(fanModes: [0: .fixed(rpm: 1500)], profile: nil))
}

@Test func configurationCarriesActiveProfile() {
    var s = AppSettings.defaults
    s.selectProfile(BuiltInProfiles.performanceID, fans: [0])
    #expect(s.helperConfiguration == HelperConfiguration(fanModes: [0: .profile], profile: BuiltInProfiles.all()[2]))
}

// MARK: - Profile editing

@Test func saveProfileInsertsAndUpdates() {
    var s = AppSettings.defaults
    var p = Profile(name: "Mine")
    s.saveProfile(p)
    #expect(s.profiles.last == p)
    p.name = "Renamed"
    s.saveProfile(p)
    #expect(s.profiles.count == 4)
    #expect(s.profiles.last?.name == "Renamed")
}

@Test func automaticProfileCannotBeEdited() {
    var s = AppSettings.defaults
    var auto = s.profiles[0]
    auto.rules = [Rule(source: .group(.cpu), curve: silent)]
    s.saveProfile(auto)
    #expect(s.profiles[0] == BuiltInProfiles.all()[0])
}

@Test func builtInsCannotBeDeleted() {
    var s = AppSettings.defaults
    for id in [BuiltInProfiles.automaticID, BuiltInProfiles.silentID, BuiltInProfiles.performanceID] {
        s.deleteProfile(id)
    }
    #expect(s.profiles == BuiltInProfiles.all())
}

@Test func deletingActiveProfileFallsBackToAutomatic() {
    var s = AppSettings.defaults
    let p = Profile(name: "Mine")
    s.saveProfile(p)
    s.fanModes = [0: .auto, 1: .fixed(rpm: 2000)]
    s.selectProfile(p.id, fans: [0, 1])
    s.deleteProfile(p.id)
    #expect(!s.profiles.contains { $0.id == p.id })
    #expect(s.activeProfileID == BuiltInProfiles.automaticID)
    #expect(s.fanModes == [0: .auto, 1: .fixed(rpm: 2000)])
}

@Test func deletingInactiveProfileKeepsSelection() {
    var s = AppSettings.defaults
    let p = Profile(name: "Mine")
    s.saveProfile(p)
    s.selectProfile(BuiltInProfiles.silentID, fans: [0])
    s.deleteProfile(p.id)
    #expect(s.activeProfileID == BuiltInProfiles.silentID)
    #expect(s.fanModes == [0: .profile])
}

// MARK: - Panel helpers

private func reading(_ id: String, _ c: Double, group: SensorGroup = .cpu, suspect: Bool = false) -> SensorReading {
    SensorReading(id: SensorID(id), rawName: id, name: id, group: group, celsius: c,
                  featured: false, safety: false, suspect: suspect)
}

@Test func hottestSkipsHiddenAndSuspect() {
    let prefs = SensorPrefs(starred: [], renamed: [:], hidden: [SensorID("a")])
    let r = [reading("a", 90), reading("b", 50), reading("c", 70), reading("d", 99, suspect: true),
             reading("e", 60), reading("f", 40)]
    #expect(prefs.hottest(r, count: 3).map(\.id.rawValue) == ["c", "e", "b"])
}

@Test func displayNamePrefersRename() {
    let prefs = SensorPrefs(starred: [], renamed: [SensorID("a"): "Board"], hidden: [])
    #expect(prefs.displayName(reading("a", 50)) == "Board")
    #expect(prefs.displayName(reading("b", 50)) == "b")
}

@Test func sourceTemperatureUsesGroupMaxIgnoringSuspect() {
    let r = [reading("a", 60), reading("b", 70), reading("c", 95, suspect: true), reading("g", 80, group: .gpu)]
    #expect(SensorSourceRef.group(.cpu).temperature(in: r) == 70)
    #expect(SensorSourceRef.sensor(SensorID("g")).temperature(in: r) == 80)
    #expect(SensorSourceRef.group(.battery).temperature(in: r) == nil)
}
