import AppKit
import XCTest

@testable import Inverso

@MainActor
final class SettingsKeysTests: XCTestCase {

    func testAllPreferenceKeysListIsCompleteAndExact() {
        XCTAssertEqual(SettingsKeys.enabledLayouts, "enabledLayouts")
        XCTAssertEqual(SettingsKeys.disabledLayoutIDs, "disabledLayoutIDs")
        XCTAssertEqual(SettingsKeys.targetOverrides, "targetOverrides")
        XCTAssertEqual(SettingsKeys.useDoubleShift, "useDoubleShift")
        XCTAssertEqual(SettingsKeys.hotkeyKeyCode, "hotkeyKeyCode")
        XCTAssertEqual(SettingsKeys.hotkeyModifiers, "hotkeyModifiers")
        XCTAssertEqual(SettingsKeys.conversionFeedback, "conversionFeedback")
        XCTAssertEqual(SettingsKeys.playSounds, "playSounds")
        XCTAssertEqual(SettingsKeys.smartConversionMode, "smartConversionMode")
        XCTAssertEqual(SettingsKeys.layoutSwitchMode, "layoutSwitchMode")
        XCTAssertEqual(SettingsKeys.conversionCount, "conversionCount")
        XCTAssertEqual(SettingsKeys.loggingEnabled, "loggingEnabled")
        XCTAssertEqual(SettingsKeys.logMaxEntries, "logMaxEntries")
        XCTAssertEqual(SettingsKeys.appLanguageOverride, "appLanguageOverride")
        XCTAssertEqual(SettingsKeys.settingsTab, "settingsTab")
        XCTAssertEqual(SettingsKeys.sparkleEnableAutomaticChecks, "SUEnableAutomaticChecks")
        XCTAssertEqual(SettingsKeys.sparkleScheduledCheckInterval, "SUScheduledCheckInterval")

        XCTAssertEqual(SettingsKeys.openSettingsAtLaunch, "LSOpenSettingsAtLaunch")
        XCTAssertEqual(SettingsKeys.demoHUD, "LSDemoHUD")
        XCTAssertEqual(SettingsKeys.hudBackground, "LSHUDBackground")

        XCTAssertEqual(
            SettingsKeys.allPreferenceKeys,
            [
                "enabledLayouts",
                "disabledLayoutIDs",
                "targetOverrides",
                "useDoubleShift",
                "hotkeyKeyCode",
                "hotkeyModifiers",
                "conversionFeedback",
                "playSounds",
                "smartConversionMode",
                "layoutSwitchMode",
                "conversionCount",
                "loggingEnabled",
                "logMaxEntries",
                "appLanguageOverride",
                "settingsTab",
                "SUEnableAutomaticChecks",
                "SUScheduledCheckInterval",
            ]
        )
        XCTAssertEqual(Set(SettingsKeys.allPreferenceKeys).count, SettingsKeys.allPreferenceKeys.count)
    }

    func testHotkeyModifiersDefaultMatchesAppKitOption() {
        XCTAssertEqual(SettingsKeys.Defaults.hotkeyModifiers, NSEvent.ModifierFlags.option.rawValue)
        XCTAssertEqual(SettingsKeys.Defaults.hotkeyModifiers, 524_288)
    }

    func testDefaultValues() {
        XCTAssertEqual(SettingsKeys.Defaults.disabledLayoutIDs, [])
        XCTAssertEqual(SettingsKeys.Defaults.targetOverrides, [:])
        XCTAssertTrue(SettingsKeys.Defaults.useDoubleShift)
        XCTAssertEqual(SettingsKeys.Defaults.hotkeyKeyCode, 0x01)
        XCTAssertEqual(SettingsKeys.Defaults.hotkeyModifiers, NSEvent.ModifierFlags.option.rawValue)
        XCTAssertEqual(SettingsKeys.Defaults.conversionFeedback, .hud)
        XCTAssertTrue(SettingsKeys.Defaults.playSounds)
        XCTAssertEqual(SettingsKeys.Defaults.smartConversionMode, .greedyLine)
        XCTAssertEqual(SettingsKeys.Defaults.layoutSwitchMode, .always)
        XCTAssertEqual(SettingsKeys.Defaults.conversionCount, 0)
        XCTAssertFalse(SettingsKeys.Defaults.loggingEnabled)
        XCTAssertEqual(SettingsKeys.Defaults.logMaxEntries, 100)
        XCTAssertEqual(SettingsKeys.Defaults.appLanguageOverride, "")
        XCTAssertTrue(SettingsKeys.Defaults.sparkleEnableAutomaticChecks)
    }

    func testSettingsManagerUsesDefaultsAndPersistsChanges() throws {
        let suiteName = "SettingsKeysTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SettingsManager(defaults: defaults)
        XCTAssertEqual(settings.disabledLayoutIDs, SettingsKeys.Defaults.disabledLayoutIDs)
        XCTAssertEqual(settings.targetOverrides, SettingsKeys.Defaults.targetOverrides)
        XCTAssertEqual(settings.useDoubleShift, SettingsKeys.Defaults.useDoubleShift)
        XCTAssertEqual(settings.hotkeyKeyCode, SettingsKeys.Defaults.hotkeyKeyCode)
        XCTAssertEqual(settings.hotkeyModifiers, SettingsKeys.Defaults.hotkeyModifiers)
        XCTAssertEqual(settings.conversionFeedback, SettingsKeys.Defaults.conversionFeedback)
        XCTAssertEqual(settings.playSounds, SettingsKeys.Defaults.playSounds)
        XCTAssertEqual(settings.smartConversionMode, SettingsKeys.Defaults.smartConversionMode)
        XCTAssertEqual(settings.layoutSwitchMode, SettingsKeys.Defaults.layoutSwitchMode)
        XCTAssertEqual(settings.conversionCount, SettingsKeys.Defaults.conversionCount)
        XCTAssertEqual(settings.loggingEnabled, SettingsKeys.Defaults.loggingEnabled)
        XCTAssertEqual(settings.logMaxEntries, SettingsKeys.Defaults.logMaxEntries)

        settings.useDoubleShift = false
        settings.hotkeyKeyCode = 0x31
        settings.hotkeyModifiers = NSEvent.ModifierFlags.command.rawValue
        settings.conversionFeedback = .notification
        settings.playSounds = false
        settings.smartConversionMode = .disabled
        settings.layoutSwitchMode = .ifLastWordConverted
        settings.incrementConversionCount()
        settings.loggingEnabled = true
        settings.logMaxEntries = 250

        let reloaded = SettingsManager(defaults: defaults)
        XCTAssertFalse(reloaded.useDoubleShift)
        XCTAssertEqual(reloaded.hotkeyKeyCode, 0x31)
        XCTAssertEqual(reloaded.hotkeyModifiers, NSEvent.ModifierFlags.command.rawValue)
        XCTAssertEqual(reloaded.conversionFeedback, .notification)
        XCTAssertFalse(reloaded.playSounds)
        XCTAssertEqual(reloaded.smartConversionMode, .disabled)
        XCTAssertEqual(reloaded.layoutSwitchMode, .ifLastWordConverted)
        XCTAssertEqual(reloaded.conversionCount, 1)
        XCTAssertTrue(reloaded.loggingEnabled)
        XCTAssertEqual(reloaded.logMaxEntries, 250)
    }
}
