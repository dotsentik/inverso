import Carbon
import CoreGraphics

/// Posts real keyboard events through Quartz.
@MainActor
struct CGEventKeystrokeSender: KeystrokeSender {

    /// Annotated session events go to the frontmost app. HID events take the path of real
    /// key presses, to the window with the keyboard focus.
    var tap: CGEventTapLocation = .cgAnnotatedSessionEventTap

    func routedToKeyWindow() -> KeystrokeSender {
        CGEventKeystrokeSender(tap: .cghidEventTap)
    }

    func send(_ keystroke: Keystroke) {
        switch keystroke {
        case .copy:
            Log.accessibility.debug("Simulating ⌘C")
            simulateKeystroke(virtualKey: kVK_ANSI_C, modifiers: .maskCommand)
        case .paste:
            Log.accessibility.debug("Simulating ⌘V")
            simulateKeystroke(virtualKey: kVK_ANSI_V, modifiers: .maskCommand)
        case .selectToLineStart:
            Log.accessibility.debug("Simulating ⌘⇧←")
            simulateKeystroke(virtualKey: kVK_LeftArrow, modifiers: [.maskShift, .maskCommand])
        case .selectWordLeft:
            Log.accessibility.debug("Simulating ⇧⌥←")
            simulateKeystroke(virtualKey: kVK_LeftArrow, modifiers: [.maskShift, .maskAlternate])
        case .rightArrow:
            Log.accessibility.debug("Simulating →")
            simulateKeystroke(virtualKey: kVK_RightArrow)
        case .typeText(let text):
            Log.accessibility.debug("Typing \(text.utf16.count) UTF-16 units")
            for chunk in Self.chunks(of: text) {
                postUnicodeEvent(chunk, keyDown: true)
                postUnicodeEvent(chunk, keyDown: false)
            }
        }
    }

    /// CGEventKeyboardSetUnicodeString takes at most 20 UTF-16 units per event. Chunks end
    /// on Character boundaries so a surrogate pair or combining sequence is never split.
    static func chunks(of text: String, maxUTF16: Int = 20) -> [[UniChar]] {
        var chunks: [[UniChar]] = []
        var current: [UniChar] = []
        for character in text {
            let units = Array(String(character).utf16)
            if !current.isEmpty && current.count + units.count > maxUTF16 {
                chunks.append(current)
                current = []
            }
            current += units
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    private func postUnicodeEvent(_ units: [UniChar], keyDown: Bool) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown) else {
            Log.accessibility.error("Failed to create CGEvent for typing (down=\(keyDown))")
            return
        }
        event.flags = []
        event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        event.post(tap: tap)
    }

    /// Key down + key up.
    private func simulateKeystroke(virtualKey: Int, modifiers: CGEventFlags = []) {
        let keyCode = CGKeyCode(virtualKey)
        postKeyEvent(virtualKey: keyCode, keyDown: true, modifiers: modifiers)
        postKeyEvent(virtualKey: keyCode, keyDown: false, modifiers: modifiers)
    }

    /// The event gets exactly `modifiers`, independent of the keys physically held: with
    /// .combinedSessionState a Shift still held from the double-Shift trigger would leak in.
    private func postKeyEvent(virtualKey: CGKeyCode, keyDown: Bool, modifiers: CGEventFlags) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: keyDown) else {
            Log.accessibility.error("Failed to create CGEvent (key=\(virtualKey), down=\(keyDown))")
            return
        }
        event.flags = modifiers
        event.post(tap: tap)
        Log.accessibility.debug(
            "Posted key event: key=0x\(String(virtualKey, radix: 16), privacy: .public), down=\(keyDown), mods=\(modifiers.rawValue), tap=\(tap == .cghidEventTap ? "hid" : "annotatedSession", privacy: .public)"
        )
    }
}
