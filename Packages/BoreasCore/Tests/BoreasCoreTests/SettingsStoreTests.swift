import Foundation
import Testing
@testable import BoreasCore

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("boreas-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func write(_ text: String, to url: URL) throws {
    try Data(text.utf8).write(to: url)
}

// MARK: - SettingsStore

@Test func corruptFileFallsBackAndIsKept() throws {
    let dir = try tempDir()
    try write("{bozuk", to: dir.appendingPathComponent("settings.json"))
    #expect(SettingsStore(directory: dir).load() == .defaults)
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(names.contains { $0.hasPrefix("settings.broken-") && $0.hasSuffix(".json") })
    #expect(!names.contains("settings.json"))
}

@Test func corruptFileTwiceKeepsBothCopies() throws {
    let dir = try tempDir()
    let store = SettingsStore(directory: dir)
    try write("{bozuk", to: dir.appendingPathComponent("settings.json"))
    _ = store.load()
    try write("[]", to: dir.appendingPathComponent("settings.json"))
    _ = store.load()
    let broken = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasPrefix("settings.broken-") }
    #expect(broken.count == 2)
}

@Test func missingFileGivesDefaults() throws {
    let dir = try tempDir()
    #expect(SettingsStore(directory: dir).load() == .defaults)
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
}

@Test func missingBuiltInsRestored() throws {
    let dir = try tempDir()
    let store = SettingsStore(directory: dir)
    let mine = Profile(name: "Mine", rules: [Rule(source: .group(.cpu), curve: silent)])
    var s = AppSettings.defaults
    s.profiles = [mine]
    s.activeProfileID = mine.id
    try store.save(s)
    let loaded = store.load()
    #expect(loaded.profiles.count == 4)
    #expect(loaded.profiles.prefix(3).map(\.id) == [BuiltInProfiles.automaticID, BuiltInProfiles.silentID, BuiltInProfiles.performanceID])
    #expect(loaded.profiles[3] == mine)
    #expect(loaded.activeProfileID == mine.id)
}

@Test func editedBuiltInIsKept() throws {
    let dir = try tempDir()
    let store = SettingsStore(directory: dir)
    var s = AppSettings.defaults
    s.profiles[1].behavior.hysteresisC = 5
    try store.save(s)
    #expect(store.load().profiles[1].behavior.hysteresisC == 5)
}

@Test func unknownActiveProfileFallsBackToAutomatic() throws {
    let dir = try tempDir()
    let store = SettingsStore(directory: dir)
    var s = AppSettings.defaults
    s.activeProfileID = UUID()
    try store.save(s)
    #expect(store.load().activeProfileID == BuiltInProfiles.automaticID)
}

@Test func roundTrip() throws {
    let dir = try tempDir()
    let store = SettingsStore(directory: dir)
    var s = AppSettings.defaults
    s.unit = .fahrenheit
    s.fanModes = [0: .fixed(rpm: 1800), 1: .profile]
    s.sensorPrefs = SensorPrefs(starred: [SensorID("hid:PMU tdie1")], renamed: [SensorID("smc:TC0P"): "Board"],
                                hidden: [SensorID("smc:TPD0")])
    s.menuBarDisplay = .both
    s.menuBarSensor = .sensor(SensorID("smc:TC0P"))
    s.sampleInterval = 2
    s.historyCollapsed = true
    try store.save(s)
    #expect(store.load() == s)
}

@Test func saveCreatesDirectory() throws {
    let dir = try tempDir().appendingPathComponent("nested/Boreas")
    let store = SettingsStore(directory: dir)
    try store.save(.defaults)
    #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.json").path))
}

// MARK: - Decoding robustness

@Test func settingsMissingNewerKeysStillDecode() throws {
    // Only some keys present: everything else takes its default instead of failing the whole file.
    let json = """
    {"unit":"fahrenheit","activeProfileID":"\(BuiltInProfiles.silentID.uuidString)",
     "fanModes":{"0":{"profile":{}}}}
    """
    let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    #expect(s.unit == .fahrenheit)
    #expect(s.activeProfileID == BuiltInProfiles.silentID)
    #expect(s.fanModes == [0: .profile])
    #expect(s.profiles == BuiltInProfiles.all())
    #expect(s.menuBarDisplay == .temperature)
    #expect(s.menuBarSensor == .group(.cpu))
    #expect(s.sampleInterval == 1)
    #expect(s.historyCollapsed == false)
    #expect(s.sensorPrefs == SensorPrefs())
}

@Test func emptyObjectDecodesToDefaults() throws {
    #expect(try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8)) == .defaults)
}

@Test func sensorPrefsMissingKeysDecode() throws {
    let p = try JSONDecoder().decode(SensorPrefs.self, from: Data(#"{"starred":["smc:TC0P"]}"#.utf8))
    #expect(p == SensorPrefs(starred: [SensorID("smc:TC0P")], renamed: [:], hidden: []))
}

@Test func renamedSensorsEncodeAsJSONObject() throws {
    let p = SensorPrefs(starred: [], renamed: [SensorID("smc:TC0P"): "Board"], hidden: [])
    let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as? [String: Any]
    #expect((obj?["renamed"] as? [String: String]) == ["smc:TC0P": "Board"])
}

@Test func defaultsMatchSpec() {
    let d = AppSettings.defaults
    #expect(d.profiles == BuiltInProfiles.all())
    #expect(d.activeProfileID == BuiltInProfiles.automaticID)
    #expect(d.fanModes.isEmpty)
    #expect(d.menuBarDisplay == .temperature)
    #expect(d.menuBarSensor == .group(.cpu))
    #expect(d.unit == .celsius)
    #expect(d.sampleInterval == 1)
    #expect(d.historyCollapsed == false)
}
