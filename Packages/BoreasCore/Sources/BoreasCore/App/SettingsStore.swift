import Foundation
import os

private let log = Logger(subsystem: "com.kaandikec.boreas", category: "settings")

/// Reads and writes `settings.json` in `directory`.
///
/// A file that cannot be read or decoded is moved aside as `settings.broken-<yyyyMMdd-HHmmss>.json`
/// and the defaults are used, so a bad file never keeps the app from starting and is never lost.
public final class SettingsStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public var fileURL: URL { directory.appendingPathComponent("settings.json") }

    public func load() -> AppSettings {
        let url = fileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return .defaults }
        do {
            var s = try JSONDecoder().decode(AppSettings.self, from: Data(contentsOf: url))
            s.normalize()
            return s
        } catch {
            log.error("settings.json unreadable, using defaults: \(String(describing: error), privacy: .public)")
            moveAside(url)
            return .defaults
        }
    }

    public func save(_ s: AppSettings) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(s).write(to: fileURL, options: .atomic)
    }

    private func moveAside(_ url: URL) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = f.string(from: Date())
        var target = directory.appendingPathComponent("settings.broken-\(stamp).json")
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = directory.appendingPathComponent("settings.broken-\(stamp)-\(n).json")
            n += 1
        }
        do {
            try FileManager.default.moveItem(at: url, to: target)
        } catch {
            log.error("could not move broken settings aside: \(String(describing: error), privacy: .public)")
        }
    }
}
