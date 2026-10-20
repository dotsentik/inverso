import SwiftUI

enum MenuShortcut {
    /// A SwiftUI shortcut for a hotkey whose key produces a plain character (letters, digits).
    static func keyboardShortcut(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> KeyboardShortcut? {
        let name = HotkeyManager.keyName(for: keyCode)
        guard name.count == 1, let char = name.lowercased().first, char.isLetter || char.isNumber else { return nil }
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        return KeyboardShortcut(KeyEquivalent(char), modifiers: eventModifiers)
    }
}
