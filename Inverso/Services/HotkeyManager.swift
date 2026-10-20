import Carbon
import Cocoa

/// Global hotkey: a modifier + key shortcut, or a double tap of Shift.
final class HotkeyManager {

    typealias Action = () -> Void

    /// Longest pause between the two Shift taps of a double Shift.
    private static let doubleTapInterval: TimeInterval = 0.4

    private static let keyNames: [Int: String] = [
        kVK_ANSI_A: "A", kVK_ANSI_S: "S", kVK_ANSI_D: "D", kVK_ANSI_F: "F", kVK_ANSI_H: "H",
        kVK_ANSI_G: "G", kVK_ANSI_Z: "Z", kVK_ANSI_X: "X", kVK_ANSI_C: "C", kVK_ANSI_V: "V",
        kVK_ANSI_B: "B", kVK_ANSI_Q: "Q", kVK_ANSI_W: "W", kVK_ANSI_E: "E", kVK_ANSI_R: "R",
        kVK_ANSI_Y: "Y", kVK_ANSI_T: "T", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_6: "6", kVK_ANSI_5: "5", kVK_ANSI_Equal: "=", kVK_ANSI_9: "9",
        kVK_ANSI_7: "7", kVK_ANSI_Minus: "-", kVK_ANSI_8: "8", kVK_ANSI_0: "0", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_O: "O", kVK_ANSI_U: "U", kVK_ANSI_LeftBracket: "[", kVK_ANSI_I: "I", kVK_ANSI_P: "P",
        kVK_ANSI_L: "L", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_Slash: "/", kVK_ANSI_N: "N",
        kVK_ANSI_M: "M", kVK_Space: "Space", kVK_Return: "Return", kVK_Tab: "Tab",
        kVK_Delete: "Delete", kVK_Escape: "Escape",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4",
        kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    private var action: Action?
    private var keyDownGlobalMonitor: Any?
    private var keyDownLocalMonitor: Any?
    private var flagsGlobalMonitor: Any?
    private var flagsLocalMonitor: Any?

    /// Uptime of the last clean Shift tap, 0 if none is pending.
    private var lastShiftTapTime: TimeInterval = 0
    /// Shift is down and nothing else has been pressed since.
    private var shiftIsDownAlone = false

    deinit {
        unregister()
    }

    // MARK: - Registration

    /// Fires `action` on two clean Shift taps (no other key or modifier in between).
    func registerDoubleShift(action: @escaping Action) {
        unregister()
        self.action = action

        flagsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        flagsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        // Any key pressed while Shift is down makes it a Shift+key chord, not a tap
        keyDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            self?.shiftIsDownAlone = false
        }
        keyDownLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.shiftIsDownAlone = false
            return event
        }
    }

    /// Fires `action` on `keyCode` with exactly `modifiers`. In our own windows the key is consumed.
    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, action: @escaping Action) {
        unregister()
        self.action = action

        let targetModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
        let matches = { (event: NSEvent) in
            event.keyCode == keyCode && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == targetModifiers
        }

        keyDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if matches(event) {
                self?.action?()
            }
        }
        keyDownLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, matches(event) else { return event }
            self.action?()
            return nil
        }
    }

    func unregister() {
        for monitor in [keyDownGlobalMonitor, keyDownLocalMonitor, flagsGlobalMonitor, flagsLocalMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        keyDownGlobalMonitor = nil
        keyDownLocalMonitor = nil
        flagsGlobalMonitor = nil
        flagsLocalMonitor = nil
        action = nil
        lastShiftTapTime = 0
        shiftIsDownAlone = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let shiftDown = flags.contains(.shift)
        let onlyShift = shiftDown && !flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control)

        if onlyShift && !shiftIsDownAlone {
            shiftIsDownAlone = true
        } else if !shiftDown && shiftIsDownAlone {
            // Released after a clean press
            shiftIsDownAlone = false
            let now = ProcessInfo.processInfo.systemUptime
            if lastShiftTapTime > 0 && now - lastShiftTapTime < Self.doubleTapInterval {
                lastShiftTapTime = 0
                action?()
            } else {
                lastShiftTapTime = now
            }
        } else if !onlyShift {
            // Another modifier is involved
            shiftIsDownAlone = false
        }
    }

    // MARK: - Display

    /// "⌃⌥⇧⌘" symbols of the modifiers, in the standard macOS order.
    static func symbols(for modifiers: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols
    }

    /// Name of the key on a US keyboard, or "Key<code>" for keys without one.
    static func keyName(for keyCode: UInt16) -> String {
        keyNames[Int(keyCode)] ?? "Key\(keyCode)"
    }
}
