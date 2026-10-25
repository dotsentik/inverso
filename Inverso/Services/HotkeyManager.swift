import Carbon
import Cocoa

/// Stateful detector that decides whether an incoming keyboard or modifier event triggers the hotkey.
protocol HotkeyTrigger {
    /// Whether this trigger needs `.flagsChanged` event monitors in addition to `.keyDown`.
    var monitorsFlagsChanged: Bool { get }
    /// Whether a matched `.keyDown` event in the app's own windows should be consumed.
    var consumesMatchedKeyDown: Bool { get }

    mutating func handleKeyDown(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) -> Bool

    mutating func handleFlagsChanged(
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) -> Bool

    mutating func reset()
}

extension HotkeyTrigger {
    var monitorsFlagsChanged: Bool { false }
    var consumesMatchedKeyDown: Bool { false }

    mutating func handleFlagsChanged(
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) -> Bool {
        false
    }

    mutating func reset() {}
}

/// Fires on two clean Shift taps within `doubleTapInterval` with no other key or modifier in between.
struct DoubleShiftTrigger: HotkeyTrigger {
    static let defaultInterval: TimeInterval = 0.4
    private static let chordModifiersMask: NSEvent.ModifierFlags = [.shift, .command, .option, .control]

    let doubleTapInterval: TimeInterval
    private(set) var lastShiftTapTime: TimeInterval = 0
    private(set) var shiftIsDownAlone = false

    var monitorsFlagsChanged: Bool { true }

    init(doubleTapInterval: TimeInterval = DoubleShiftTrigger.defaultInterval) {
        self.doubleTapInterval = doubleTapInterval
    }

    mutating func handleKeyDown(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) -> Bool {
        if shiftIsDownAlone {
            shiftIsDownAlone = false
        }
        return false
    }

    mutating func handleFlagsChanged(
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) -> Bool {
        let flags = modifierFlags.intersection(Self.chordModifiersMask)
        if flags == .shift {
            if !shiftIsDownAlone {
                shiftIsDownAlone = true
            }
            return false
        }

        if !flags.contains(.shift) && shiftIsDownAlone {
            // Released after a clean press
            shiftIsDownAlone = false
            if lastShiftTapTime > 0 && timestamp - lastShiftTapTime < doubleTapInterval {
                lastShiftTapTime = 0
                return true
            }
            lastShiftTapTime = timestamp
            return false
        }

        if shiftIsDownAlone {
            // Another modifier is involved
            shiftIsDownAlone = false
        }
        return false
    }

    mutating func reset() {
        lastShiftTapTime = 0
        shiftIsDownAlone = false
    }
}

/// Fires when a specific `keyCode` is pressed with exact device-independent `modifiers`.
struct KeyChordTrigger: HotkeyTrigger {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    var consumesMatchedKeyDown: Bool { true }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    }

    mutating func handleKeyDown(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) -> Bool {
        guard keyCode == self.keyCode else { return false }
        return modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers
    }
}

/// Global hotkey: a modifier + key shortcut, or a double tap of Shift.
final class HotkeyManager {

    typealias Action = () -> Void

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

    private var trigger: (any HotkeyTrigger)?
    private var action: Action?
    private var keyDownGlobalMonitor: Any?
    private var keyDownLocalMonitor: Any?
    private var flagsGlobalMonitor: Any?
    private var flagsLocalMonitor: Any?

    deinit {
        unregister()
    }

    // MARK: - Registration

    /// Fires `action` on two clean Shift taps (no other key or modifier in between).
    func registerDoubleShift(action: @escaping Action) {
        register(trigger: DoubleShiftTrigger(), action: action)
    }

    /// Fires `action` on `keyCode` with exactly `modifiers`. In our own windows the key is consumed.
    func register(keyCode: UInt16, modifiers: NSEvent.ModifierFlags, action: @escaping Action) {
        register(trigger: KeyChordTrigger(keyCode: keyCode, modifiers: modifiers), action: action)
    }

    /// Registers a custom `HotkeyTrigger` and installs only the required `NSEvent` monitors.
    func register(trigger: some HotkeyTrigger, action: @escaping Action) {
        unregister()
        self.trigger = trigger
        self.action = action

        if trigger.monitorsFlagsChanged {
            flagsGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.processFlagsChanged(event)
            }
            flagsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                self?.processFlagsChanged(event)
                return event
            }
        }

        keyDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            _ = self?.processKeyDown(event)
        }
        keyDownLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let matched = self.processKeyDown(event)
            return (matched && (self.trigger?.consumesMatchedKeyDown ?? false)) ? nil : event
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
        trigger?.reset()
        trigger = nil
        action = nil
    }

    @discardableResult
    private func processKeyDown(_ event: NSEvent) -> Bool {
        guard
            var currentTrigger = trigger
        else { return false }
        let matched = currentTrigger.handleKeyDown(
            keyCode: event.keyCode,
            modifierFlags: event.modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        trigger = currentTrigger
        if matched {
            action?()
        }
        return matched
    }

    private func processFlagsChanged(_ event: NSEvent) {
        guard var currentTrigger = trigger else { return }
        let matched = currentTrigger.handleFlagsChanged(
            modifierFlags: event.modifierFlags,
            timestamp: ProcessInfo.processInfo.systemUptime
        )
        trigger = currentTrigger
        if matched {
            action?()
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
