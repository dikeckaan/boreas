import BoreasCore
import Foundation

func fail(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((msg + "\n").utf8))
    exit(code)
}

let usage = """
kullanım: boreasctl <komut>
  fans                         fan tablosu
  keys [önek]                  SMC anahtarları (anahtar, tip, değer)
  auto                         tüm fanları Otomatik'e al (sudo)
  set <fan> <rpm> --hold <sn>  fanı elle sür, süre dolunca Otomatik'e dön (sudo, en fazla 120 sn)
"""

func hex(_ b: [UInt8]) -> String { b.map { String(format: "%02x", $0) }.joined() }

func printFans(_ fc: FanController) throws {
    for f in try fc.fans() {
        print(String(format: "fan %d  actual %6.0f  min %5.0f  max %5.0f  target %6.0f  %@",
                     f.index, f.actual, f.min, f.max, f.target, f.isManual ? "elle" : "otomatik"))
    }
}

func requireRoot() {
    if geteuid() != 0 { fail("sudo ile çalıştırın", code: 77) }
}

let command: CLICommand
do { command = try CLICommand.parse(Array(CommandLine.arguments.dropFirst())) }
catch { fail("\(error)") }

if command == .help { print(usage); exit(0) }

if case .set = command { requireRoot() }
if command == .auto { requireRoot() }

let smc: IOKitSMCClient
do { smc = try IOKitSMCClient() } catch { fail("SMC açılamadı: \(error)") }
let fc = FanController(smc: smc)

/// Restores auto mode with read-back; retries once, then warns loudly. Returns true if verified.
@discardableResult
func restoreAuto(alsoFans: [Int] = []) -> Bool {
    var left = fc.setAllAuto(alsoFans: alsoFans)
    if !left.isEmpty { left = fc.setAllAuto(alsoFans: Array(Set(left + alsoFans))) }
    if !left.isEmpty {
        FileHandle.standardError.write(Data("UYARI: fan \(left.map(String.init).joined(separator: ", ")) Otomatik'e alınamadı veya doğrulanamadı! Macs Fan Control veya yeniden başlatma ile geri alın.\n".utf8))
    }
    return left.isEmpty
}

do {
    switch command {
    case .fans:
        try printFans(fc)
    case .keys(let prefix):
        for k in try smc.allKeys() where prefix.map({ k.description.hasPrefix($0) }) ?? true {
            guard let v = try? smc.read(k) else { continue }
            let shown = v.doubleValue.map { String($0) } ?? hex(v.bytes)
            print("\(k)  \(v.type)  \(shown)")
        }
    case .auto:
        let ok = restoreAuto()
        try printFans(fc)
        if !ok { exit(1) }
    case .set(let fan, let rpm, let hold):
        // Restore auto mode before dying on SIGINT/SIGTERM.
        var sources: [DispatchSourceSignal] = []
        for sig in [SIGINT, SIGTERM, SIGHUP, SIGQUIT] {
            signal(sig, SIG_IGN)
            let s = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            s.setEventHandler {
                restoreAuto(alsoFans: [fan])
                exit(128 + sig)
            }
            s.resume()
            sources.append(s)
        }
        do { try fc.setManual(fan: fan, rpm: rpm) }
        catch { restoreAuto(alsoFans: [fan]); fail("elle moda alınamadı: \(error)") }
        var remaining = hold
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0)
        timer.setEventHandler {
            try? printFans(fc)
            if remaining <= 0 {
                let ok = restoreAuto(alsoFans: [fan])
                try? printFans(fc)
                exit(ok ? 0 : 1)
            }
            remaining -= 1
        }
        timer.resume()
        dispatchMain()
    case .help:
        break
    }
} catch {
    fail("\(error)")
}
