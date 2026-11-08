// BoreasHelper: root LaunchDaemon that owns the fan control loop.
//
// Threading model: `HelperRuntime` is not thread-safe. Everything that touches it runs on
// `HelperService.queue`, one serial queue: the 1 s tick timer, signal sources, IOKit power
// notifications (delivered there via IONotificationPortSetDispatchQueue) and XPC calls (which
// arrive on XPC's own queues and hop onto it before touching the runtime).

import BoreasCore
import Foundation
import IOKit
import IOKit.pwr_mgt
import MachO
import os

private let log = Logger(subsystem: "com.kaandikec.boreas.helper", category: "helper")

// IOKit's message macros are not imported into Swift: iokit_common_msg(m) == 0xE0000000 | m.
private let messageCanSystemSleep: UInt32 = 0xE000_0270
private let messageSystemWillSleep: UInt32 = 0xE000_0280
private let messageSystemHasPoweredOn: UInt32 = 0xE000_0300

/// The Info.plist linked into this executable's `__TEXT,__info_plist` section. Read directly:
/// the helper lives in Boreas.app/Contents/MacOS, so `Bundle.main`'s URLs point at the app and
/// the source of the Team ID should not depend on how Foundation resolves the main bundle.
/// (`Bundle.main.resourceURL` being the app's Resources is where `SensorCatalog.bundled()` finds
/// `BoreasCore_BoreasCore.bundle`; if it is missing, the helper refuses manual control.)
private func embeddedInfoPlist() -> [String: Any] {
    var size: UInt = 0
    let header = #dsohandle.assumingMemoryBound(to: mach_header_64.self)
    guard let bytes = getsectiondata(header, "__TEXT", "__info_plist", &size), size > 0 else { return [:] }
    let data = Data(bytes: bytes, count: Int(size))
    return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
}

/// Only Boreas.app signed by our team may connect. nil (refuse everyone) if the Team ID is
/// missing or malformed; it is also validated so it cannot inject into the requirement string.
/// Release builds also require the Developer ID markers (Developer ID CA intermediate and
/// Developer ID Application leaf); Debug builds keep the plain requirement so development-signed
/// apps can still connect.
private func clientRequirement(teamID: String?) -> String? {
    guard let teamID, teamID.count == 10,
          teamID.allSatisfy({ ("A"..."Z").contains($0) || ("0"..."9").contains($0) }) else { return nil }
    let base = "anchor apple generic and identifier \"com.kaandikec.boreas\" and certificate leaf[subject.OU] = \"\(teamID)\""
    #if DEBUG
    return base
    #else
    return base + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
        + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
    #endif
}

/// Monotonic, keeps counting during sleep, never jumps with wall-clock changes.
private func monotonicNow() -> Date {
    Date(timeIntervalSinceReferenceDate: Double(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1e9)
}

/// Exported to each client connection. Every call hops onto the runtime queue and first tells
/// the connection's tracker that a message arrived: a connection becomes a client only then,
/// i.e. after XPC has checked the code-signing requirement.
final class XPCHandler: NSObject, BoreasHelperXPC, @unchecked Sendable {
    private let queue: DispatchQueue
    private let runtime: HelperRuntime
    private let tracker: ConnectionTracker
    private let version: String

    init(queue: DispatchQueue, runtime: HelperRuntime, tracker: ConnectionTracker, version: String) {
        self.queue = queue
        self.runtime = runtime
        self.tracker = tracker
        self.version = version
    }

    func snapshot(reply: @escaping @Sendable (Data?) -> Void) {
        queue.async {
            self.tracker.messageReceived()
            reply(try? JSONEncoder().encode(self.runtime.snapshot()))
        }
    }

    func apply(configuration: Data, reply: @escaping @Sendable (String?) -> Void) {
        queue.async {
            self.tracker.messageReceived()
            do {
                // nil, or why the runtime refused it (sensor catalog unavailable).
                reply(self.runtime.apply(try JSONDecoder().decode(HelperConfiguration.self, from: configuration)))
            } catch {
                reply("Invalid configuration: \(error)")
            }
        }
    }

    func resetAllToAuto(reply: @escaping @Sendable () -> Void) {
        queue.async {
            self.tracker.messageReceived()
            self.runtime.resetAllToAuto()
            reply()
        }
    }

    func version(reply: @escaping @Sendable (String) -> Void) {
        queue.async {
            self.tracker.messageReceived()
            reply(self.version)
        }
    }
}

final class HelperService: NSObject, NSXPCListenerDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.kaandikec.boreas.helper.runtime")
    private let runtime: HelperRuntime
    private let version: String
    private let requirement: String?
    private let listener = NSXPCListener(machServiceName: boreasHelperMachServiceName)
    private var timer: DispatchSourceTimer?
    private var signalSources: [DispatchSourceSignal] = []
    private var rootPort: io_connect_t = 0

    init(runtime: HelperRuntime, version: String, requirement: String?) {
        self.runtime = runtime
        self.version = version
        self.requirement = requirement
    }

    func start() {
        // Safety resets (signals, sleep) are in place before any client can apply a configuration.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [runtime] in
            runtime.tick()
            if runtime.shouldExit {
                log.info("idle, exiting")
                exit(0)
            }
        }
        timer.resume()
        self.timer = timer

        for sig in [SIGTERM, SIGINT, SIGHUP, SIGQUIT] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: queue)
            source.setEventHandler { [runtime] in
                runtime.shutdown()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }

        registerForSystemPower()

        if let requirement {
            listener.setConnectionCodeSigningRequirement(requirement)
        } else {
            log.error("BoreasTeamID missing from the embedded Info.plist; refusing all connections")
        }
        listener.delegate = self
        listener.resume()
    }

    // MARK: NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let requirement else { return false }
        connection.setCodeSigningRequirement(requirement)
        connection.exportedInterface = NSXPCInterface(with: BoreasHelperXPC.self)
        // Created here but only used on `queue`. It counts the client on the first message and
        // un-counts it at most once, and only if it was counted.
        let tracker = ConnectionTracker(runtime: runtime)
        connection.exportedObject = XPCHandler(queue: queue, runtime: runtime, tracker: tracker, version: version)
        let ended: @Sendable () -> Void = { [queue] in queue.async { tracker.connectionEnded() } }
        connection.invalidationHandler = ended
        connection.interruptionHandler = ended
        connection.resume()
        return true
    }

    // MARK: Power

    private func registerForSystemPower() {
        var port: IONotificationPortRef?
        var notifier: io_object_t = 0
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        rootPort = IORegisterForSystemPower(refcon, &port, { refcon, _, messageType, messageArgument in
            guard let refcon else { return }
            Unmanaged<HelperService>.fromOpaque(refcon).takeUnretainedValue()
                .handlePower(messageType: messageType, argument: messageArgument)
        }, &notifier)
        guard rootPort != 0, let port else {
            log.error("IORegisterForSystemPower failed; sleep/wake resets unavailable")
            return
        }
        // Callbacks are delivered on the runtime queue.
        IONotificationPortSetDispatchQueue(port, queue)
    }

    /// Runs on `queue`.
    private func handlePower(messageType: UInt32, argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case messageCanSystemSleep:
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case messageSystemWillSleep:
            defer { IOAllowPowerChange(rootPort, Int(bitPattern: argument)) }
            runtime.willSleep()
        case messageSystemHasPoweredOn:
            runtime.didWake()
        default:
            break
        }
    }
}

// MARK: - Entry point

let info = embeddedInfoPlist()
let helperVersion = info["CFBundleShortVersionString"] as? String ?? "0"

let smc: IOKitSMCClient
do { smc = try IOKitSMCClient() } catch {
    log.fault("cannot open AppleSMC: \(String(describing: error), privacy: .public)")
    // exit(0): launchd's KeepAlive(SuccessfulExit=false) would otherwise respawn this every 10 s.
    // The next client message launches the helper again on demand.
    exit(0)
}

// Fans back to auto before anything else can go wrong (sensor setup included). HelperRuntime's
// init does it again and records anything it cannot confirm.
let fans = FanController(smc: smc)
fans.setAllAuto()

// Created before any event source exists; from here on only touched on service.queue.
// Without its sensor catalog the helper fails closed: every fan stays automatic.
let sensors = SensorReader.live(language: "en")
if !sensors.catalogLoaded { log.fault("sensor catalog unavailable; manual fan control disabled") }
let runtime = HelperRuntime(fans: fans, sensors: sensors, now: monotonicNow, helperVersion: helperVersion,
                            catalogAvailable: sensors.catalogLoaded)
let service = HelperService(runtime: runtime, version: helperVersion,
                            requirement: clientRequirement(teamID: info["BoreasTeamID"] as? String))
service.start()
dispatchMain()
