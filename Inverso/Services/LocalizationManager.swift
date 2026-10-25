import Foundation

/// UI strings from Resources/Localizable.xcstrings (en + ru). The language follows the system
/// unless the user picks one in Settings, which switches the UI instantly without a restart.
///
/// String(localized:) alone can't do that: it always uses the system's preferred languages.
/// Here an explicit choice reads from that language's .lproj bundle.
@MainActor
final class LocalizationManager: ObservableObject {

    static let shared = LocalizationManager()

    /// `currentLanguage` value meaning "use the system language".
    static let systemLanguage = SettingsKeys.Defaults.appLanguageOverride

    /// Languages the user can pick explicitly: code + native name.
    static let availableLanguages: [(code: String, name: String)] = [
        ("en", "English"),
        ("ru", "Русский"),
    ]

    /// UserDefaults key of the explicit choice. The old "appLanguage" key is ignored on purpose:
    /// earlier versions always wrote it, so it cannot tell a real choice from the detected default.
    static let overrideKey = SettingsKeys.appLanguageOverride

    private static let fallbackLanguage = "en"

    /// Explicitly chosen language code, or `systemLanguage`.
    @Published var currentLanguage: String {
        didSet {
            if currentLanguage == Self.systemLanguage {
                defaults.removeObject(forKey: Self.overrideKey)
            } else {
                defaults.set(currentLanguage, forKey: Self.overrideKey)
            }
            stringsBundle = Self.stringsBundle(for: currentLanguage, in: mainBundle)
        }
    }

    private let mainBundle: Bundle
    private let defaults: UserDefaults
    private var stringsBundle: Bundle

    init(bundle: Bundle = .main, defaults: UserDefaults = .standard) {
        mainBundle = bundle
        self.defaults = defaults
        var language = Self.systemLanguage
        if let saved = defaults.string(forKey: Self.overrideKey),
            Self.availableLanguages.contains(where: { $0.code == saved })
        {
            language = saved
        }
        currentLanguage = language
        stringsBundle = Self.stringsBundle(for: language, in: bundle)
    }

    /// Language actually used for the UI.
    var effectiveLanguage: String {
        currentLanguage == Self.systemLanguage
            ? (mainBundle.preferredLocalizations.first ?? Self.fallbackLanguage)
            : currentLanguage
    }

    /// Locale for SwiftUI views (dates, numbers, system-provided strings).
    var locale: Locale {
        currentLanguage == Self.systemLanguage ? .autoupdatingCurrent : Locale(identifier: currentLanguage)
    }

    /// The string for `key` in the current language; falls back to English, then to the key itself.
    func localized(_ key: String) -> String {
        let value = stringsBundle.localizedString(forKey: key, value: nil, table: nil)
        if value != key { return value }
        if let english = Self.lprojBundle(Self.fallbackLanguage, in: mainBundle) {
            let value = english.localizedString(forKey: key, value: nil, table: nil)
            if value != key { return value }
        }
        return key
    }

    // MARK: - Bundles

    /// The app bundle itself follows the system's preferred languages; an explicit
    /// choice reads from that language's .lproj.
    private static func stringsBundle(for language: String, in bundle: Bundle) -> Bundle {
        guard language != systemLanguage else { return bundle }
        return lprojBundle(language, in: bundle) ?? bundle
    }

    private static func lprojBundle(_ language: String, in bundle: Bundle) -> Bundle? {
        bundle.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
    }
}
