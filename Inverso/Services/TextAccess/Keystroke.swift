import Foundation

/// Keystrokes the conversion chain sends to the frontmost app.
enum Keystroke: Equatable {
    /// ⌘C
    case copy
    /// ⌘V
    case paste
    /// ⌘⇧←
    case selectToLineStart
    /// ⇧⌥←
    case selectWordLeft
    /// → (collapses the selection to its end)
    case rightArrow
    /// Types the text as Unicode key events, replacing the selection.
    case typeText(String)
}
