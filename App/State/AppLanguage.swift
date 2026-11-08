import Foundation

/// The language the app's UI runs in (`en` or `tr`). It follows the app's own localization, which
/// can differ from the system locale (for example `-AppleLanguages "(tr)"` on an English system).
enum AppLanguage {
    static let code = Bundle.main.preferredLocalizations.first ?? "en"
    static let locale = Locale(identifier: code)

    /// Localized in the app's language and upper-cased by its rules (Turkish `i` → `İ`), for
    /// section headers.
    static func uppercased(_ resource: LocalizedStringResource) -> String {
        var r = resource
        r.locale = locale
        return String(localized: r).uppercased(with: locale)
    }
}
