/// UserDefaults keys and default values used across the app.
enum SettingsKeys {
    /// Stores `layoutOrder`; the old name is kept for compatibility.
    static let enabledLayouts = "enabledLayouts"
    static let disabledLayoutIDs = "disabledLayoutIDs"
    static let targetOverrides = "targetOverrides"
    static let useDoubleShift = "useDoubleShift"
    static let hotkeyKeyCode = "hotkeyKeyCode"
    static let hotkeyModifiers = "hotkeyModifiers"
    static let conversionFeedback = "conversionFeedback"
    static let playSounds = "playSounds"
    static let smartConversionMode = "smartConversionMode"
    static let layoutSwitchMode = "layoutSwitchMode"
    static let conversionCount = "conversionCount"
    static let loggingEnabled = "loggingEnabled"
    static let logMaxEntries = "logMaxEntries"
    static let appLanguageOverride = "appLanguageOverride"
    static let settingsTab = "settingsTab"
    static let sparkleEnableAutomaticChecks = "SUEnableAutomaticChecks"
    static let sparkleScheduledCheckInterval = "SUScheduledCheckInterval"

    static let openSettingsAtLaunch = "LSOpenSettingsAtLaunch"
    static let demoHUD = "LSDemoHUD"
    static let hudBackground = "LSHUDBackground"

    /// All persistent user preference keys.
    static let allPreferenceKeys: [String] = [
        enabledLayouts,
        disabledLayoutIDs,
        targetOverrides,
        useDoubleShift,
        hotkeyKeyCode,
        hotkeyModifiers,
        conversionFeedback,
        playSounds,
        smartConversionMode,
        layoutSwitchMode,
        conversionCount,
        loggingEnabled,
        logMaxEntries,
        appLanguageOverride,
        settingsTab,
        sparkleEnableAutomaticChecks,
        sparkleScheduledCheckInterval,
    ]

    enum Defaults {
        static let disabledLayoutIDs: Set<String> = []
        static let targetOverrides: [String: String] = [:]
        static let useDoubleShift = true
        /// ANSI S key (0x01), used with Option when double Shift is off.
        static let hotkeyKeyCode: UInt16 = 0x01
        /// `NSEvent.ModifierFlags.option.rawValue`, written out so this file does not need AppKit.
        static let hotkeyModifiers: UInt = 1 << 19
        static let conversionFeedback: ConversionFeedback = .hud
        static let playSounds = true
        static let smartConversionMode: SmartConversionMode = .greedyLine
        static let layoutSwitchMode: LayoutSwitchMode = .always
        static let conversionCount = 0
        static let loggingEnabled = false
        static let logMaxEntries = 100
        static let appLanguageOverride = ""
        static let sparkleEnableAutomaticChecks = true
    }
}
