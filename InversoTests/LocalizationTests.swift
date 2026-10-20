import XCTest

@testable import Inverso

@MainActor
final class LocalizationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "LocalizationTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    // MARK: - String Catalog

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    private func catalog() throws -> [String: [String: String]] {
        let url = repoRoot.appendingPathComponent("Inverso/Resources/Localizable.xcstrings")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let strings = try XCTUnwrap(json["strings"] as? [String: [String: Any]])
        var result: [String: [String: String]] = [:]
        for (key, entry) in strings {
            let localizations = entry["localizations"] as? [String: [String: [String: String]]] ?? [:]
            result[key] = localizations.compactMapValues { $0["stringUnit"]?["value"] }
        }
        return result
    }

    private func keysUsedInSources() throws -> Set<String> {
        let sources = repoRoot.appendingPathComponent("Inverso")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        let regex = try NSRegularExpression(pattern: #"\.localized\("([^"]+)"\)"#)
        var keys = Set<String>()
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                keys.insert((text as NSString).substring(with: match.range(at: 1)))
            }
        }
        return keys
    }

    func testEveryUsedKeyIsTranslatedToEnglishAndRussian() throws {
        let catalog = try catalog()
        let used = try keysUsedInSources()
        XCTAssertGreaterThan(used.count, 50)
        for key in used.sorted() {
            let values = catalog[key]
            XCTAssertNotNil(values, "'\(key)' missing from Localizable.xcstrings")
            XCTAssertFalse(values?["en"]?.isEmpty ?? true, "'\(key)' has no English value")
            XCTAssertFalse(values?["ru"]?.isEmpty ?? true, "'\(key)' has no Russian value")
        }
    }

    func testPlaceholdersMatchBetweenLanguages() throws {
        let regex = try NSRegularExpression(pattern: "%[@d]")
        func placeholders(_ s: String) -> [String] {
            regex.matches(in: s, range: NSRange(s.startIndex..., in: s)).map {
                (s as NSString).substring(with: $0.range)
            }
        }
        for (key, values) in try catalog() {
            XCTAssertEqual(placeholders(values["en"] ?? ""), placeholders(values["ru"] ?? ""), key)
        }
    }

    // MARK: - LocalizationManager

    func testDefaultFollowsSystem() {
        let manager = LocalizationManager(defaults: defaults)
        XCTAssertEqual(manager.currentLanguage, LocalizationManager.systemLanguage)
        XCTAssertEqual(manager.effectiveLanguage, Bundle.main.preferredLocalizations.first)
    }

    func testExplicitLanguagesFromCatalog() {
        let manager = LocalizationManager(defaults: defaults)
        manager.currentLanguage = "ru"
        XCTAssertEqual(manager.localized("menu.quit"), "Завершить Inverso")
        XCTAssertEqual(manager.localized("log.column.output"), "Стало")
        manager.currentLanguage = "en"
        XCTAssertEqual(manager.localized("menu.quit"), "Quit Inverso")
    }

    func testUnknownKeyReturnsKey() {
        let manager = LocalizationManager(defaults: defaults)
        manager.currentLanguage = "ru"
        XCTAssertEqual(manager.localized("no.such.key"), "no.such.key")
    }

    func testChoiceIsPersistedAndSystemClearsIt() {
        let manager = LocalizationManager(defaults: defaults)
        manager.currentLanguage = "ru"
        XCTAssertEqual(defaults.string(forKey: LocalizationManager.overrideKey), "ru")
        XCTAssertEqual(LocalizationManager(defaults: defaults).currentLanguage, "ru")

        manager.currentLanguage = LocalizationManager.systemLanguage
        XCTAssertNil(defaults.string(forKey: LocalizationManager.overrideKey))
    }

    func testLegacyAutoDetectedLanguageIsIgnored() {
        defaults.set("ru", forKey: "appLanguage")
        XCTAssertEqual(LocalizationManager(defaults: defaults).currentLanguage, LocalizationManager.systemLanguage)
    }

    func testUnsupportedSavedLanguageFallsBackToSystem() {
        defaults.set("fr", forKey: LocalizationManager.overrideKey)
        XCTAssertEqual(LocalizationManager(defaults: defaults).currentLanguage, LocalizationManager.systemLanguage)
    }

    func testLocaleMatchesExplicitChoice() {
        let manager = LocalizationManager(defaults: defaults)
        manager.currentLanguage = "ru"
        XCTAssertEqual(manager.locale.language.languageCode, "ru")
    }
}
