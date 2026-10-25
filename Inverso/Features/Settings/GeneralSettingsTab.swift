import SwiftUI

/// Language, launch at login, feedback, Smart Conversion and layout switch modes.
struct GeneralSettingsTab: View {
    @ObservedObject var launchAtLogin: LaunchAtLoginHelper
    @ObservedObject var updates: UpdateController
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var l10n: LocalizationManager

    var body: some View {
        Form {
            Section {
                Picker(l10n.localized("general.language"), selection: $l10n.currentLanguage) {
                    Text(l10n.localized("general.language.system")).tag(LocalizationManager.systemLanguage)
                    Divider()
                    ForEach(LocalizationManager.availableLanguages, id: \.code) { lang in
                        Text(lang.name).tag(lang.code)
                    }
                }

                Toggle(
                    l10n.localized("general.launchAtLogin"),
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    ))
                if launchAtLogin.requiresApproval {
                    LabeledContent {
                        Button(l10n.localized("general.launchAtLoginOpenSettings")) {
                            launchAtLogin.openSystemSettings()
                        }
                    } label: {
                        Label(
                            l10n.localized("general.launchAtLoginRequiresApproval"),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .symbolRenderingMode(.multicolor)
                    }
                }
                if let error = launchAtLogin.lastError {
                    Label(
                        l10n.localized("general.launchAtLoginError").replacingOccurrences(of: "%@", with: error),
                        systemImage: "xmark.octagon.fill"
                    )
                    .symbolRenderingMode(.multicolor)
                }

            }

            Section {
                Toggle(
                    l10n.localized("general.automaticUpdateChecks"),
                    isOn: Binding(
                        get: { updates.automaticallyChecksForUpdates },
                        set: { updates.setAutomaticallyChecksForUpdates($0) }
                    ))
            } footer: {
                Text(l10n.localized("general.automaticUpdateChecks.footer"))
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(l10n.localized("general.feedback"), selection: $settingsManager.conversionFeedback) {
                    Text(l10n.localized("general.feedback.hud")).tag(ConversionFeedback.hud)
                    Text(l10n.localized("general.feedback.notification")).tag(ConversionFeedback.notification)
                    Text(l10n.localized("general.feedback.none")).tag(ConversionFeedback.none)
                }
                .help(l10n.localized("general.feedback.help"))
                .onChange(of: settingsManager.conversionFeedback) { _, feedback in
                    if feedback == .notification { ConversionCoordinator.requestNotificationAuthorization() }
                }
                Toggle(l10n.localized("general.playSound"), isOn: $settingsManager.playSounds)
            }

            Section {
                Picker(l10n.localized("general.mode"), selection: $settingsManager.smartConversionMode) {
                    ForEach(SmartConversionMode.allCases, id: \.self) { mode in
                        Text(smartModeDisplayName(mode)).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(l10n.localized("general.smartConversion"))
            } footer: {
                Text(smartModeDescription(settingsManager.smartConversionMode))
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker(l10n.localized("general.mode"), selection: $settingsManager.layoutSwitchMode) {
                    ForEach(LayoutSwitchMode.allCases, id: \.self) { mode in
                        Text(layoutSwitchModeDisplayName(mode)).tag(mode)
                    }
                }
                .pickerStyle(.radioGroup)
            } header: {
                Text(l10n.localized("general.layoutSwitch"))
            } footer: {
                Text(layoutSwitchModeDescription(settingsManager.layoutSwitchMode))
                    .foregroundStyle(.secondary)
            }

            Section(l10n.localized("general.statistics")) {
                LabeledContent(l10n.localized("general.totalConversions")) {
                    Text(settingsManager.conversionCount, format: .number)
                        .monospacedDigit()
                }
            }
        }
        .formStyle(.grouped)
        .settingsFormFrame()
        .onAppear { launchAtLogin.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin.refresh()
        }
    }

    // MARK: - Mode Names
    // Read through the l10n environment object so the view re-renders on a language change.

    private func smartModeDisplayName(_ mode: SmartConversionMode) -> String {
        switch mode {
        case .lastWord: return l10n.localized("smartMode.lastWord.name")
        case .greedyLine: return l10n.localized("smartMode.greedyLine.name")
        case .disabled: return l10n.localized("smartMode.disabled.name")
        }
    }

    private func smartModeDescription(_ mode: SmartConversionMode) -> String {
        switch mode {
        case .lastWord: return l10n.localized("smartMode.lastWord.desc")
        case .greedyLine: return l10n.localized("smartMode.greedyLine.desc")
        case .disabled: return l10n.localized("smartMode.disabled.desc")
        }
    }

    private func layoutSwitchModeDisplayName(_ mode: LayoutSwitchMode) -> String {
        switch mode {
        case .always: return l10n.localized("layoutSwitchMode.always.name")
        case .ifLastWordConverted: return l10n.localized("layoutSwitchMode.ifLastWord.name")
        case .ifAnyWordConverted: return l10n.localized("layoutSwitchMode.ifAnyWord.name")
        }
    }

    private func layoutSwitchModeDescription(_ mode: LayoutSwitchMode) -> String {
        switch mode {
        case .always: return l10n.localized("layoutSwitchMode.always.desc")
        case .ifLastWordConverted: return l10n.localized("layoutSwitchMode.ifLastWord.desc")
        case .ifAnyWordConverted: return l10n.localized("layoutSwitchMode.ifAnyWord.desc")
        }
    }
}
