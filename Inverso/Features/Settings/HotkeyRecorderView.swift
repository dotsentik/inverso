import Carbon
import SwiftUI

/// Records a custom shortcut: the next key pressed with at least one modifier.
struct HotkeyRecorderView: View {
    let keyCode: UInt16
    let modifiers: NSEvent.ModifierFlags
    /// Called once with the accepted shortcut.
    let onRecord: (UInt16, NSEvent.ModifierFlags) -> Void
    @EnvironmentObject private var l10n: LocalizationManager
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var rejection: Rejection?

    /// Why a recorded combination is refused.
    enum Rejection: Equatable {
        /// No ⌘, ⌥ or ⌃: a bare key or ⇧+key would fire while typing.
        case needsModifier
        /// The conversion itself sends this shortcut (copy, paste, select a line or a word).
        case reserved
        /// ⌘ + key alone is an app command (⌘Q, ⌘S, ⌘W): the hotkey is swallowed system-wide,
        /// so recording it would disable that command in every app.
        case commandOnly

        var localizationKey: String {
            switch self {
            case .needsModifier: return "hotkeyRecorder.needsModifier"
            case .reserved: return "hotkeyRecorder.reserved"
            case .commandOnly: return "hotkeyRecorder.commandOnly"
            }
        }
    }

    /// The modifiers that count for a shortcut: Caps Lock, numeric pad, Fn and Help are not part of it.
    static let relevantModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

    /// nil = acceptable.
    static func rejection(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Rejection? {
        let mods = flags.intersection(relevantModifiers)
        guard !mods.isDisjoint(with: [.command, .option, .control]) else { return .needsModifier }
        let key = Int(keyCode)
        switch mods {
        case [.command] where key == kVK_ANSI_C || key == kVK_ANSI_V:
            return .reserved
        case [.command, .shift] where key == kVK_LeftArrow:
            return .reserved
        case [.shift, .option] where key == kVK_LeftArrow || key == kVK_RightArrow:
            return .reserved
        case [.command]:
            return .commandOnly
        default:
            return nil
        }
    }

    var body: some View {
        LabeledContent(l10n.localized("hotkeyRecorder.prompt")) {
            HStack {
                if isRecording, let rejection {
                    Text(l10n.localized(rejection.localizationKey))
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text(isRecording ? l10n.localized("hotkeyRecorder.pressKey") : currentShortcutDescription)
                    .foregroundStyle(isRecording ? .secondary : .primary)

                Button(isRecording ? l10n.localized("hotkeyRecorder.cancel") : l10n.localized("hotkeyRecorder.record"))
                {
                    if isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                }
            }
        }
        .onDisappear { stopRecording() }
    }

    private var currentShortcutDescription: String {
        HotkeyManager.symbols(for: modifiers) + HotkeyManager.keyName(for: keyCode)
    }

    private func startRecording() {
        isRecording = true
        rejection = nil
        // The hotkey tap would swallow the current shortcut before this monitor sees it.
        NotificationCenter.default.post(name: .hotkeyRecordingStarted, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let eventMods = event.modifierFlags.intersection(Self.relevantModifiers)

            // Escape without modifiers cancels recording
            if Int(event.keyCode) == kVK_Escape && eventMods.isEmpty {
                stopRecording()
                return nil
            }

            // A key without any modifier is ordinary typing: let it through
            guard !eventMods.isEmpty else { return event }

            if let rejection = Self.rejection(keyCode: event.keyCode, flags: eventMods) {
                self.rejection = rejection
                return nil  // Consume the event and keep recording
            }
            onRecord(event.keyCode, eventMods)
            stopRecording()
            return nil  // Consume the event
        }
    }

    private func stopRecording() {
        let wasRecording = isRecording
        isRecording = false
        rejection = nil
        if wasRecording {
            NotificationCenter.default.post(name: .hotkeyRecordingEnded, object: nil)
        }
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
