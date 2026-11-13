import Foundation

/// When the system keyboard layout switches after a conversion. Raw values are stored in UserDefaults.
enum LayoutSwitchMode: Int, CaseIterable, Codable {
    case always = 0
    /// If the last word was in the wrong layout and got converted.
    case ifLastWordConverted = 1
    /// If any word of the converted text needed conversion.
    case ifAnyWordConverted = 2

    /// Whether to switch the layout after `original` was converted into `converted`.
    ///
    /// Only words with a letter count ("ghbdtn 45": the last word is "ghbdtn"); such a word is
    /// converted when it changed. Conversion maps characters one to one and keeps whitespace,
    /// so the words of both strings line up.
    func shouldSwitchLayout(original: String, converted: String) -> Bool {
        let originalWords = original.split(whereSeparator: \.isWhitespace)
        let convertedWords = converted.split(whereSeparator: \.isWhitespace)
        let changed = zip(originalWords, convertedWords)
            .filter { before, after in before.contains(where: \.isLetter) || after.contains(where: \.isLetter) }
            .map { before, after in before != after }
        switch self {
        case .always:
            return true
        case .ifLastWordConverted:
            return changed.last ?? false
        case .ifAnyWordConverted:
            return changed.contains(true)
        }
    }
}
