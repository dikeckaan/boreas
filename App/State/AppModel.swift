import BoreasCore
import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.kaandikec.boreas", category: "app")

/// Root state of the app.
///
/// Every `settings.sampleInterval` seconds it takes a snapshot: from the helper when it is
/// enabled, otherwise locally (sensors via `SensorReader.live`, fans read-only via
/// `FanController`). Settings are saved on every change, and the resulting
/// `HelperConfiguration` is sent to the helper whenever it changes or the connection is new.
@MainActor @Observable
final class AppModel {
    private(set) var snapshot: HelperSnapshot?
    private(set) var history = HistoryBuffer()
    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            persist()
            if settings.helperConfiguration != oldValue.helperConfiguration {
                Task { await syncConfiguration() }
            }
        }
    }
    private(set) var helperStatus: HelperStatus = .notRegistered
    /// True when the current snapshot was read locally (helper not enabled or not answering).
    private(set) var isLocal = true
    /// Last helper communication error (snapshot failed), nil once a snapshot succeeds again.
    private(set) var helperError: String?
    /// Last configuration the helper refused or did not receive, nil once one is accepted.
    private(set) var configurationError: String?
    /// Error from the last install attempt, shown by the onboarding view and Settings.
    private(set) var installError: String?
    /// The last Remove stopped because the fans could not be reset; Settings offers "Remove Anyway".
    private(set) var removeNeedsForce = false
    /// Number of fans, nil until the first reading.
    private(set) var fanCount: Int?

    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let client = HelperClient()
    @ObservationIgnored private let installer = HelperInstaller()
    @ObservationIgnored private var localReader: LocalReader?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private var lastStatusCheck: ContinuousClock.Instant?
    /// Connection generation and configuration the helper last accepted.
    @ObservationIgnored private var sentGeneration: UInt64?
    @ObservationIgnored private var sentConfiguration: HelperConfiguration?
    @ObservationIgnored private var syncing = false
    /// Gate for helper traffic: blocked during Remove/Reinstall, and for a new connection until it
    /// has answered a snapshot and passed the version check.
    @ObservationIgnored private let lifecycle = HelperLifecycle()
    @ObservationIgnored private var versionChecked = false
    @ObservationIgnored private var quitting = false
    /// Set when `register()` failed because the daemon plist or executable is missing.
    @ObservationIgnored private var registrationMissing = false
    /// The first-launch welcome window opens once per run (MenuBarLabel).
    @ObservationIgnored var welcomeShown = false
    @ObservationIgnored private let approvalGuide = ApprovalGuidePanel()
    /// Sensor names are always resolved here, in the user's language, never taken from the helper.
    @ObservationIgnored private let catalog: SensorCatalog
    @ObservationIgnored private let language: String

    static let statusCheckInterval: Duration = .seconds(3)

    #if DEBUG
    /// Debug builds launched with `-BoreasLocalOnly YES` never touch the helper or SMAppService:
    /// read-only local readings only (for checking the UI without the daemon).
    static let localOnly = UserDefaults.standard.bool(forKey: "BoreasLocalOnly")
    #else
    static let localOnly = false
    #endif

    init(store: SettingsStore = AppModel.defaultStore()) {
        self.store = store
        self.settings = store.load()
        self.catalog = (try? SensorCatalog.bundled()) ?? SensorCatalog(entries: [])
        self.language = Bundle.main.preferredLocalizations.first ?? "en"
        setUpLoginItemOnFirstLaunch()
    }

    /// Launch at login is on by default, set up once. After that the user's choice (System Settings
    /// or the Settings window) is left alone. Debug local-only runs never touch it.
    private func setUpLoginItemOnFirstLaunch() {
        guard LoginItemPolicy.shouldRegisterOnThisLaunch(didInitialSetup: settings.didInitialLoginItemSetup,
                                                         localOnly: Self.localOnly) else { return }
        LoginItem.performInitialSetup()
        settings.didInitialLoginItemSetup = true
        persist()   // explicit: do not rely on didSet alone for "never register again"
    }

    static func defaultStore() -> SettingsStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return SettingsStore(directory: base.appendingPathComponent("Boreas", isDirectory: true))
    }

    // MARK: - Derived state

    var fans: [FanInfo] { snapshot?.fans ?? [] }
    var hasFans: Bool { (fanCount ?? 0) > 0 }
    var canControlFans: Bool { hasFans && helperStatus == .enabled }
    /// What to tell the user about the helper, if anything is wrong.
    var helperProblem: String? { helperError ?? configurationError }
    /// Onboarding covers install, approval and the "missing from the app" failure.
    var needsOnboarding: Bool {
        hasFans && helperStatus != .enabled
    }

    func mode(of fan: Int) -> FanMode { settings.fanModes[fan] ?? .auto }

    // MARK: - Actions

    func selectProfile(_ id: UUID) {
        settings.selectProfile(id, fans: fans.map(\.index))
    }

    func setFanMode(_ fan: Int, _ m: FanMode) {
        settings.setFanMode(fan, m)
    }

    func saveProfile(_ p: Profile) {
        settings.saveProfile(p)
    }

    func deleteProfile(_ id: UUID) {
        settings.deleteProfile(id)
    }

    func installHelper() async {
        guard hasFans, !Self.localOnly else { return }
        installError = nil
        do {
            try await installer.register()
            registrationMissing = false
        } catch {
            log.error("register failed: \(String(describing: error), privacy: .public)")
            installError = error.localizedDescription
            if HelperStatus.isMissingRegistrationError(error) { registrationMissing = true }
        }
        await refreshStatus()
        // Registration that only awaits approval is not an error for the user.
        if helperStatus == .requiresApproval || helperStatus == .enabled { installError = nil }
    }

    /// Fans back to Apple first, then the helper is unregistered. If the reset fails the helper
    /// stays registered, the error is shown and `removeNeedsForce` is set; `force` (Remove Anyway)
    /// unregisters regardless.
    func removeHelper(force: Bool = false) async {
        guard !Self.localOnly, !lifecycle.removing else { return }
        installError = nil
        removeNeedsForce = false
        let ok = await tearDownHelper(force: force)
        if ok { await refreshStatus() }
        lifecycle.finish()
    }

    /// Remove, then install again. A failed reset does not stop it; its error stays visible.
    func reinstallHelper() async {
        guard !Self.localOnly, !lifecycle.removing else { return }
        installError = nil
        removeNeedsForce = false
        let ok = await tearDownHelper(force: true)
        if ok { await refreshStatus() }
        let resetError = installError
        if ok { await installHelper() }
        if installError == nil { installError = resetError }
        lifecycle.finish()
    }

    /// Waits out an in-flight configuration send, then runs the teardown. False when it stopped
    /// early (reset failed without `force`).
    private func tearDownHelper(force: Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(3)
        while syncing, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let outcome = await lifecycle.teardown(HelperSteps(client: client, installer: installer),
                                               isEnabled: helperStatus == .enabled,
                                               isRegistered: helperStatus != .notRegistered,
                                               force: force)
        client.invalidate()
        sentGeneration = nil
        if let reset = outcome.resetError {
            log.error("resetAllToAuto before removal failed: \(reset, privacy: .public)")
            installError = reset
        }
        if outcome.needsForce {
            removeNeedsForce = true
            return false
        }
        if let e = outcome.unregisterError {
            log.error("unregister failed: \(e, privacy: .public)")
            installError = e
        } else if outcome.unregistered {
            registrationMissing = false
        }
        return true
    }

    /// Opens Login Items and floats a small guide next to it until the helper is enabled.
    func openSystemSettings() {
        installer.openSystemSettings()
        approvalGuide.show()
    }

    // Sensor display preferences (they only change what the app shows).

    func toggleStar(_ id: SensorID) {
        if settings.sensorPrefs.starred.contains(id) {
            settings.sensorPrefs.starred.remove(id)
        } else {
            settings.sensorPrefs.starred.insert(id)
        }
    }

    func setHidden(_ id: SensorID, _ hidden: Bool) {
        if hidden { settings.sensorPrefs.hidden.insert(id) } else { settings.sensorPrefs.hidden.remove(id) }
    }

    /// An empty name removes the rename.
    func rename(_ id: SensorID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.sensorPrefs.renamed[id] = trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Loop

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                let interval = Swift.max(0.5, self.settings.sampleInterval)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    /// Fans back to Apple (2 s timeout, failure ignored), then the connection is closed.
    func prepareToQuit() async {
        quitting = true
        approvalGuide.close()
        loop?.cancel()
        loop = nil
        // Let an in-flight configuration send finish so it cannot land after the reset.
        let deadline = ContinuousClock.now + .seconds(2)
        while syncing, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if helperStatus == .enabled {
            do {
                try await client.resetAllToAuto()
            } catch {
                log.error("resetAllToAuto on quit failed: \(String(describing: error), privacy: .public)")
            }
        }
        client.invalidate()
    }

    private func tick() async {
        if quitting || lifecycle.removing { return }
        await refreshStatusIfDue()
        if lifecycle.removing { return }
        if helperStatus == .enabled {
            do {
                let s = try await client.snapshot()
                if quitting || lifecycle.removing { return }
                helperError = nil
                record(s)
                // Configuration goes out only once this connection has answered and the helper
                // is known to speak this app's format.
                if await checkVersion(s.helperVersion, formatVersion: s.formatVersion), !lifecycle.removing {
                    lifecycle.markReady(generation: client.connectionGeneration())
                    await syncConfiguration()
                }
                return
            } catch {
                log.error("snapshot failed: \(String(describing: error), privacy: .public)")
                helperError = error.localizedDescription
            }
        }
        await readLocally()
    }

    private func record(_ received: HelperSnapshot) {
        var s = received
        s.sensors = received.sensors.map { catalog.localized($0, language: language) }
        snapshot = s
        isLocal = false
        fanCount = s.fans.count
        history.append(HistorySample(date: Date(), readings: s.sensors, fans: s.fans,
                                     starred: settings.sensorPrefs.starred))
    }

    private func readLocally() async {
        let reader: LocalReader
        if let localReader {
            reader = localReader
        } else {
            let language = self.language
            reader = await Task.detached(priority: .utility) { LocalReader(language: language) }.value
            localReader = reader
        }
        let reading = await Task.detached(priority: .utility) { reader.read() }.value
        if quitting { return }
        snapshot = HelperSnapshot(fans: reading.fans,
                                  sensors: reading.sensors.map { catalog.localized($0, language: language) }, commands: [:],
                                  ceilingTripped: false, helperVersion: "")
        isLocal = true
        if let count = reading.fanCount { fanCount = count }
        history.append(HistorySample(date: Date(), readings: reading.sensors, fans: reading.fans,
                                     starred: settings.sensorPrefs.starred))
    }

    // MARK: - Helper status and configuration

    /// While the helper is not enabled (or failing), its status is re-checked every few seconds.
    private func refreshStatusIfDue() async {
        if Self.localOnly { return }
        if helperStatus == .enabled, helperError == nil, lastStatusCheck != nil { return }
        if let last = lastStatusCheck, ContinuousClock.now - last < Self.statusCheckInterval { return }
        await refreshStatus()
    }

    private func refreshStatus() async {
        lastStatusCheck = ContinuousClock.now
        let new = await installer.status(registrationMissing: registrationMissing)
        if new != helperStatus {
            log.info("helper status: \(String(describing: new), privacy: .public)")
            helperStatus = new
            // The guide only makes sense while the switch is waiting to be flipped.
            if new != .requiresApproval { approvalGuide.close() }
            if new != .enabled {
                client.invalidate()
                lifecycle.connectionLost()
                sentGeneration = nil
            }
        }
    }

    /// Sends the configuration if the helper has not accepted this one on this connection yet.
    private func syncConfiguration() async {
        guard helperStatus == .enabled, !syncing, !quitting, !lifecycle.removing else { return }
        syncing = true
        defer { syncing = false }
        while !quitting, !lifecycle.removing {
            let generation = client.connectionGeneration()
            guard lifecycle.canSync(generation: generation) else { return }
            let configuration = settings.helperConfiguration
            if generation == sentGeneration, configuration == sentConfiguration { return }
            do {
                try await client.apply(configuration)
                sentGeneration = generation
                sentConfiguration = configuration
                configurationError = nil
            } catch {
                log.error("apply failed: \(String(describing: error), privacy: .public)")
                configurationError = error.localizedDescription
                return
            }
        }
    }

    /// Once per launch: a helper from another app version, or speaking another XPC format, is
    /// unregistered and registered again.
    /// Returns false when the helper was just re-registered (this connection is gone).
    private func checkVersion(_ helperVersion: String, formatVersion: Int) async -> Bool {
        guard !versionChecked else { return true }
        versionChecked = true
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        guard helperVersion != appVersion || formatVersion != boreasXPCFormatVersion else { return true }
        log.notice("helper \(helperVersion, privacy: .public) (format \(formatVersion)) != app \(appVersion, privacy: .public) (format \(boreasXPCFormatVersion)), re-registering")
        client.invalidate()
        lifecycle.connectionLost()
        sentGeneration = nil
        do {
            try await installer.unregister()
            try await installer.register()
        } catch {
            log.error("re-register failed: \(String(describing: error), privacy: .public)")
            helperError = error.localizedDescription
            if HelperStatus.isMissingRegistrationError(error) {
                registrationMissing = true
                installError = error.localizedDescription
            }
        }
        await refreshStatus()
        return false
    }

    private func persist() {
        do {
            try store.save(settings)
        } catch {
            log.error("saving settings failed: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Read-only local readings for when the helper is not in use. Only touched by one task at a time
/// (the model's loop awaits each read).
private final class LocalReader: @unchecked Sendable {
    struct Reading: Sendable {
        let sensors: [SensorReading]
        let fans: [FanInfo]
        /// nil when the SMC could not be opened.
        let fanCount: Int?
    }

    private let sensors: SensorReader
    private let fans: FanController?

    init(language: String) {
        sensors = SensorReader.live(language: language)
        fans = (try? IOKitSMCClient()).map { FanController(smc: $0) }
    }

    func read() -> Reading {
        let count = fans?.fanCount
        let infos = (count ?? 0) > 0 ? ((try? fans?.fans()) ?? []) : []
        return Reading(sensors: sensors.read(), fans: infos, fanCount: count)
    }
}

/// Remove/Reinstall steps over the real client and `SMAppService`.
@MainActor
private struct HelperSteps: HelperServiceSteps {
    let client: HelperClient
    let installer: HelperInstaller

    func resetAllToAuto() async throws { try await client.resetAllToAuto() }
    func unregister() async throws { try await installer.unregister() }
}
