import Carbon
import SwiftUI

/// Records a custom shortcut: the next key pressed with at least one modifier.
struct HotkeyRecorderView: View {
    @Binding var keyCode: UInt16
    @Binding var modifiers: NSEvent.ModifierFlags
    @EnvironmentObject private var l10n: LocalizationManager
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        LabeledContent(l10n.localized("hotkeyRecorder.prompt")) {
            HStack {
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
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let eventMods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            // Escape without modifiers cancels recording
            if Int(event.keyCode) == kVK_Escape && eventMods.isEmpty {
                stopRecording()
                return nil
            }

            // Require at least one modifier
            if eventMods.contains(.command) || eventMods.contains(.option) || eventMods.contains(.control)
                || eventMods.contains(.shift)
            {
                self.keyCode = event.keyCode
                self.modifiers = eventMods
                stopRecording()

                NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)

                return nil  // Consume the event
            }

            return event
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
