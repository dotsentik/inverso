import SwiftUI

/// Settings tab with the Accessibility permission status and how to grant it.
struct PermissionsView: View {
    @EnvironmentObject private var l10n: LocalizationManager
    @State private var hasAccessibility = AccessibilityService.hasAccessibilityPermission

    /// Privacy & Security → Accessibility pane of System Settings.
    /// Force unwrap is safe: the string is a constant, valid URL.
    private static let accessibilitySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
    /// The user grants access in System Settings while this tab stays open; poll for it.
    private static let refreshInterval: TimeInterval = 2

    var body: some View {
        Form {
            Section {
                LabeledContent(l10n.localized("permissions.accessibilityTitle")) {
                    Label(
                        hasAccessibility
                            ? l10n.localized("permissions.grantedShort")
                            : l10n.localized("permissions.notGrantedShort"),
                        systemImage: hasAccessibility ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .symbolRenderingMode(.multicolor)
                }
                .accessibilityElement(children: .combine)

                Button(l10n.localized("permissions.openAccessibility")) {
                    NSWorkspace.shared.open(Self.accessibilitySettingsURL)
                }
                if !hasAccessibility {
                    Button(l10n.localized("permissions.requestPrompt")) {
                        AccessibilityService.requestAccessibilityPermission()
                    }
                }
            } footer: {
                Text(
                    hasAccessibility ? l10n.localized("permissions.granted") : l10n.localized("permissions.description")
                )
                .foregroundStyle(.secondary)
            }

            if !hasAccessibility {
                Section(l10n.localized("permissions.howToEnable")) {
                    Text(l10n.localized("permissions.step1"))
                    Text(l10n.localized("permissions.step2"))
                    Text(l10n.localized("permissions.step3"))
                    Text(l10n.localized("permissions.step4"))
                }
            }
        }
        .formStyle(.grouped)
        .settingsFormFrame()
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .onReceive(Timer.publish(every: Self.refreshInterval, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
    }

    private func refresh() {
        let granted = AccessibilityService.hasAccessibilityPermission
        if granted != hasAccessibility {
            hasAccessibility = granted
        }
    }
}
