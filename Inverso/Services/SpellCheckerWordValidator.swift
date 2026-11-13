import AppKit

/// `WordValidating` through the system spell checker and its installed dictionaries.
@MainActor
final class SpellCheckerWordValidator: WordValidating {

    private let checker: NSSpellChecker

    init(checker: NSSpellChecker = .shared) {
        self.checker = checker
    }

    func isWord(_ word: String, languageCode: String) -> Bool? {
        guard let language = dictionaryLanguage(for: languageCode) else { return nil }
        let misspelled = checker.checkSpelling(
            of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0,
            wordCount: nil)
        return misspelled.location == NSNotFound
    }

    /// The installed dictionary for a language code: "en" matches "en" or "en_US".
    private func dictionaryLanguage(for languageCode: String) -> String? {
        let available = checker.availableLanguages
        if available.contains(languageCode) { return languageCode }
        return available.first { $0.hasPrefix(languageCode + "_") }
    }
}
