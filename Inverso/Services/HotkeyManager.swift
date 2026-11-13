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

/// Fires when a specific `keyCode` is pressed with exactly `modifiers` (⌘⌥⌃⇧ only:
/// Caps Lock, Fn and the numeric-pad flag never take part in the match).
struct KeyChordTrigger: HotkeyTrigger, Sendable {
    /// The modifiers a shortcut is made of.
    static let chordModifiersMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags

    var consumesMatchedKeyDown: Bool { true }

    init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(Self.chordModifiersMask)
    }

    mutating func handleKeyDown(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
    ) -> Bool {
        matches(keyCode: keyCode, modifierFlags: modifierFlags)
    }

    func matches(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags) -> Bool {
        keyCode == self.keyCode && modifierFlags.intersection(Self.chordModifiersMask) == modifiers
    }
}

/// Global hotkey: a modifier + key shortcut, or a double tap of Shift.
/// A shortcut is caught by an active event tap that swallows the key press, so the focused
/// app never types it (⌥S would type "ß" over the selection). Without the tap (no
/// Accessibility permission) and for Double Shift, NSEvent monitors observe the events;
/// they deliver on the main thread but cannot swallow them.
@MainActor
final class HotkeyManager {

    typealias Action = () -> Void

    nonisolated private static let keyNames: [Int: String] = [
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
    private var keyDownTap: KeyDownTap?
    /// Polls for the Accessibility permission while a shortcut runs on monitors instead of the tap.
    private var permissionWaitTask: Task<Void, Never>?
    private static let permissionPollInterval: Duration = .seconds(2)

    isolated deinit {
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
                MainActor.assumeIsolated { self?.processFlagsChanged(event) }
            }
            flagsLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                MainActor.assumeIsolated { self?.processFlagsChanged(event) }
                return event
            }
        }

        if let chord = trigger as? KeyChordTrigger {
            keyDownTap = KeyDownTap(chord: chord) { [weak self] in self?.action?() }
            if keyDownTap != nil { return }
            Log.app.notice(
                "Hotkey event tap unavailable (no Accessibility permission?); the shortcut will not be swallowed")
            waitForAccessibilityPermission(chord: chord)
        }

        keyDownGlobalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { _ = self?.processKeyDown(event) }
        }
        keyDownLocalMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                let matched = self.processKeyDown(event)
                return matched && (self.trigger?.consumesMatchedKeyDown ?? false)
            }
            return consumed ? nil : event
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
        keyDownTap?.invalidate()
        keyDownTap = nil
        permissionWaitTask?.cancel()
        permissionWaitTask = nil
        trigger?.reset()
        trigger = nil
        action = nil
    }

    /// The tap cannot be created before the Accessibility permission is granted, which on the
    /// first launch happens after the hotkey is registered. Once it is, swap the monitors for the tap.
    private func waitForAccessibilityPermission(chord: KeyChordTrigger) {
        permissionWaitTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.permissionPollInterval)
                guard !Task.isCancelled, AXIsProcessTrusted() else { continue }
                guard let self, let action = self.action else { return }
                Log.app.info("Accessibility permission granted, installing the hotkey event tap")
                self.register(trigger: chord, action: action)
                return
            }
        }
    }

    @discardableResult
    private func processKeyDown(_ event: NSEvent) -> Bool {
        guard var currentTrigger = trigger else { return false }
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
    nonisolated static func symbols(for modifiers: NSEvent.ModifierFlags) -> String {
        var symbols = ""
        if modifiers.contains(.control) { symbols += "⌃" }
        if modifiers.contains(.option) { symbols += "⌥" }
        if modifiers.contains(.shift) { symbols += "⇧" }
        if modifiers.contains(.command) { symbols += "⌘" }
        return symbols
    }

    /// Name of the key on a US keyboard, or "Key<code>" for keys without one.
    nonisolated static func keyName(for keyCode: UInt16) -> String {
        keyNames[Int(keyCode)] ?? "Key\(keyCode)"
    }
}

/// An active keyDown event tap that swallows `chord` system-wide, so the focused app never types it.
///
/// The system waits for a tap's answer on every key press in every app, so the tap runs on its
/// own thread: a busy main thread (AX calls, SwiftUI) must not add latency to all typing. The
/// callback only compares the immutable chord and hops to the main actor on a match.
private final class KeyDownTap: @unchecked Sendable {
    // @unchecked: `chord` and `onMatch` are immutable. `port` and `source` are set once in init
    // before the thread starts and only read afterwards. `runLoop` is written once on the tap
    // thread before init returns (the semaphore orders it) and only read afterwards.
    private let chord: KeyChordTrigger
    private let onMatch: @MainActor @Sendable () -> Void
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?

    /// Nil when the tap cannot be created, e.g. without the Accessibility permission.
    init?(chord: KeyChordTrigger, onMatch: @escaping @MainActor @Sendable () -> Void) {
        self.chord = chord
        self.onMatch = onMatch
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        // Unretained: callbacks only run inside CFRunLoopRun on the tap thread, whose closure
        // keeps this object alive.
        guard
            let port = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: mask,
                callback: KeyDownTap.callback,
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else { return nil }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return nil
        }
        self.port = port
        self.source = source

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            let runLoop = CFRunLoopGetCurrent()
            self.runLoop = runLoop
            CFRunLoopAddSource(runLoop, self.source, .commonModes)
            if let port = self.port { CGEvent.tapEnable(tap: port, enable: true) }
            ready.signal()
            // Returns once the port is invalidated: its source is the run loop's only one.
            CFRunLoopRun()
        }
        thread.name = "Inverso hotkey tap"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()
    }

    /// Stops the tap; the thread exits. Safe to call from any thread, more than once.
    func invalidate() {
        if let port {
            CGEvent.tapEnable(tap: port, enable: false)
            CFMachPortInvalidate(port)
        }
        if let runLoop { CFRunLoopStop(runLoop) }
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        let tap = Unmanaged<KeyDownTap>.fromOpaque(userInfo).takeUnretainedValue()
        return tap.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
    }

    /// Runs on the tap thread. Returns true to swallow the event.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system turns a slow tap off; turn it back on.
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return false
        case .keyDown:
            // Keystrokes the conversion chain posts itself are never the hotkey.
            guard event.getIntegerValueField(.eventSourceUnixProcessID) != Int64(getpid()) else { return false }
            let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
            let flags = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            guard chord.matches(keyCode: keyCode, modifierFlags: flags) else { return false }
            // A held shortcut's auto-repeats are swallowed too, but fire only once.
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                let onMatch = self.onMatch
                Task { @MainActor in onMatch() }
            }
            return true
        default:
            return false
        }
    }
}
