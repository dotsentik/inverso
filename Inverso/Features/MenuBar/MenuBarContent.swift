import SwiftUI

/// The menu of the status item.
struct MenuBarContent: View {
    let onConvert: () -> Void

    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var l10n: LocalizationManager
    @ObservedObject private var inputSource = InputSourceMonitor.shared
    @ObservedObject private var updates = UpdateController.shared
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        convertButton

        Divider()

        Section(l10n.localized("menu.activeLayouts")) {
            ForEach(settingsManager.enabledLayouts) { layout in
                Toggle(
                    layout.localizedName,
                    isOn: Binding(
                        get: { inputSource.currentLayoutID == layout.id },
                        set: { isOn in
                            if isOn { KeyboardLayoutDetector.switchLayout(to: layout.id) }
                        }
                    ))
            }
        }

        Divider()

        Button(l10n.localized("menu.settings")) {
            NSApp.activate()
            openSettings()
        }
        .keyboardShortcut(",")

        Button(l10n.localized("menu.about")) {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(options: AboutPanel.options(l10n: l10n))
        }

        Button(l10n.localized("menu.checkForUpdates")) {
            NSApp.activate()
            updates.checkForUpdates()
        }
        .disabled(!updates.canCheckForUpdates)

        Divider()

        Button(l10n.localized("menu.quit")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Shows the conversion hotkey as the item's key equivalent when it can be one;
    /// Double Shift and keys without a character are appended to the title instead.
    @ViewBuilder
    private var convertButton: some View {
        let title = l10n.localized("menu.convertText")
        if !settingsManager.useDoubleShift,
            let shortcut = MenuShortcut.keyboardShortcut(
                keyCode: settingsManager.hotkeyKeyCode,
                modifiers: settingsManager.hotkeyModifierFlags
            )
        {
            Button(title, action: onConvert)
                .keyboardShortcut(shortcut)
        } else {
            let shortcut = settingsManager.useDoubleShift ? "⇧⇧" : settingsManager.hotkeyDescription
            Button("\(title)  \(shortcut)", action: onConvert)
        }
    }
}
