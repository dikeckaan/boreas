import Foundation

public enum AppInstallLocation {
    /// True when the app bundle lives inside `/Applications` (any depth).
    public static func isInApplications(_ bundleURL: URL) -> Bool {
        bundleURL.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix("/Applications/")
    }
}
