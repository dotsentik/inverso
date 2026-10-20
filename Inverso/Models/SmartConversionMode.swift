import Foundation

/// What the hotkey converts when no text is selected. Raw values are stored in UserDefaults.
enum SmartConversionMode: Int, CaseIterable, Codable {
    /// Only the word before the cursor.
    case lastWord = 0
    /// Select to line start, find where the wrong layout begins, convert from there.
    case greedyLine = 1
    /// Nothing: only an explicit selection converts.
    case disabled = 2
}
