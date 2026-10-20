import SwiftUI

/// The Settings window: one fixed-size area with a segmented section switcher.
struct SettingsView: View {
    enum TabID: String, CaseIterable {
        case general, layouts, shortcut, permissions, log

        var titleKey: String {
            switch self {
            case .general: return "settings.tab.general"
            case .layouts: return "settings.tab.layouts"
            case .shortcut: return "settings.tab.hotkey"
            case .permissions: return "settings.tab.permissions"
            case .log: return "settings.tab.log"
            }
        }
    }

    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var l10n: LocalizationManager
    /// The window reopens on the last used section.
    @AppStorage("settingsTab") private var selectedTab: TabID = .general

    /// One size for every section: the window never resizes when switching.
    static let windowContentSize = CGSize(width: 640, height: 560)

    var body: some View {
        content
            .frame(width: Self.windowContentSize.width, height: Self.windowContentSize.height)
            // Switching sections is instant: no size animation, no jumps
            .transaction { $0.animation = nil }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker(l10n.localized("settings.windowTitle"), selection: $selectedTab) {
                        ForEach(TabID.allCases, id: \.self) { tab in
                            Text(l10n.localized(tab.titleKey)).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.large)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .background { sectionShortcuts }
            .navigationTitle(l10n.localized(selectedTab.titleKey))
            .environment(\.locale, l10n.locale)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .general: GeneralSettingsTab()
        case .layouts: LayoutsSettingsTab()
        case .shortcut: HotkeySettingsTab()
        case .permissions: PermissionsView()
        case .log: ConversionLogView(logStore: ConversionLogStore.shared)
        }
    }

    /// ⌘1…⌘5 switch sections (invisible buttons that only carry the shortcuts).
    private var sectionShortcuts: some View {
        ForEach(Array(TabID.allCases.enumerated()), id: \.element) { index, tab in
            Button(l10n.localized(tab.titleKey)) { selectedTab = tab }
                .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        }
        .opacity(0)
        .accessibilityHidden(true)
    }
}
