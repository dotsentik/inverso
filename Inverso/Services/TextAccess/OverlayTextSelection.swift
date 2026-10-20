import Foundation

/// Selects the text before the cursor through AX in Spotlight and Open/Save panels, where
/// keystrokes may not reach the field. Offsets are UTF-16, like AX ranges.
enum OverlayTextSelection {

    /// Value and selection of the focused field.
    struct State: Equatable {
        var value: String
        var selectedRange: NSRange
    }

    /// Spotlight completes the typed text inline: the suggested tail is selected, from the
    /// end of the typed text to the end of the value. A selection the user made at the end of
    /// the text, not starting at its beginning, looks the same and is treated the same way.
    static func isInlineCompletion(_ state: State) -> Bool {
        let range = state.selectedRange
        return range.location != NSNotFound && range.location > 0 && range.length > 0
            && NSMaxRange(range) == state.value.utf16.count
    }

    /// Where the typed text ends: the caret, or the start of an inline completion.
    /// nil while the user has a selection of their own.
    static func cursor(in state: State) -> Int? {
        let range = state.selectedRange
        guard range.location != NSNotFound, NSMaxRange(range) <= state.value.utf16.count else { return nil }
        if range.length == 0 || isInlineCompletion(state) { return range.location }
        return nil
    }

    /// What `keystroke` would select, ending at the cursor: the word to the left with the
    /// whitespace after it (⇧⌥←), or the text from the line start (⌘⇧←). An inline completion
    /// after the cursor is not included. nil if there is nothing before the cursor.
    static func rangeBeforeCursor(_ keystroke: Keystroke, in state: State) -> NSRange? {
        guard let cursor = cursor(in: state), cursor > 0 else { return nil }
        let units = Array(state.value.utf16)
        var start = cursor
        switch keystroke {
        case .selectToLineStart:
            while start > 0, !isNewline(units[start - 1]) { start -= 1 }
        case .selectWordLeft:
            while start > 0, isWhitespace(units[start - 1]) { start -= 1 }
            while start > 0, !isWhitespace(units[start - 1]) { start -= 1 }
        default:
            return nil
        }
        guard start < cursor else { return nil }
        return NSRange(location: start, length: cursor - start)
    }

    // Surrogate halves are neither, so a character outside the BMP is never split.
    private static func isWhitespace(_ unit: UTF16.CodeUnit) -> Bool {
        Unicode.Scalar(unit).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
    }

    private static func isNewline(_ unit: UTF16.CodeUnit) -> Bool {
        Unicode.Scalar(unit).map { CharacterSet.newlines.contains($0) } ?? false
    }
}
