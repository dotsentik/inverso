import SwiftUI

/// Double Shift or a custom shortcut.
struct HotkeySettingsTab: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var l10n: LocalizationManager

    var body: some View {
        Form {
            Section {
                LabeledContent(l10n.localized("hotkey.current")) {
                    Text(settingsManager.hotkeyDescription)
                }
            } footer: {
                Text(l10n.localized("hotkey.description"))
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(l10n.localized("hotkey.useDoubleShift"), isOn: $settingsManager.useDoubleShift)
            } footer: {
                Text(l10n.localized("hotkey.doubleShiftHint"))
                    .foregroundStyle(.secondary)
            }

            if !settingsManager.useDoubleShift {
                Section(l10n.localized("hotkey.customTitle")) {
                    HotkeyRecorderView(
                        keyCode: $settingsManager.hotkeyKeyCode,
                        modifiers: Binding(
                            get: { settingsManager.hotkeyModifierFlags },
                            set: { settingsManager.hotkeyModifierFlags = $0 }
                        )
                    )
                }
            }
        }
        .formStyle(.grouped)
        .settingsFormFrame()
    }
}
