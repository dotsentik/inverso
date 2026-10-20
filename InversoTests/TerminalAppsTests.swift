import XCTest

@testable import Inverso

final class TerminalAppsTests: XCTestCase {

    func testListContainsExactlyTheSupportedTerminals() {
        XCTAssertEqual(
            TerminalApps.bundleIDs,
            [
                "com.apple.Terminal",
                "com.googlecode.iterm2",
                "com.mitchellh.ghostty",
                "dev.warp.Warp-Stable",
                "net.kovidgoyal.kitty",
                "org.alacritty",
                "com.github.wez.wezterm",
            ])
    }

    func testMatchesEveryListedTerminal() {
        for bundleID in TerminalApps.bundleIDs {
            XCTAssertTrue(TerminalApps.matches(bundleID: bundleID), bundleID)
        }
    }

    func testOtherAppsAreNotTerminals() {
        XCTAssertFalse(TerminalApps.matches(bundleID: "com.apple.TextEdit"))
        XCTAssertFalse(TerminalApps.matches(bundleID: "com.microsoft.VSCode"))
        XCTAssertFalse(TerminalApps.matches(bundleID: "com.apple.terminal"), "bundle IDs are case-sensitive")
        XCTAssertFalse(TerminalApps.matches(bundleID: nil))
    }

    func testTerminalInFrontHasFocus() {
        XCTAssertTrue(TerminalApps.hasFocus(frontmostBundleID: "com.apple.Terminal", overlayFocused: false))
    }

    /// Spotlight or an Open/Save panel above a terminal takes the keyboard focus.
    func testOverlayAboveTerminalHasFocus() {
        XCTAssertFalse(TerminalApps.hasFocus(frontmostBundleID: "com.apple.Terminal", overlayFocused: true))
    }

    func testOtherAppInFront() {
        XCTAssertFalse(TerminalApps.hasFocus(frontmostBundleID: "com.apple.TextEdit", overlayFocused: false))
    }

    @MainActor
    func testHintIsLocalized() {
        let manager = LocalizationManager(defaults: UserDefaults(suiteName: "TerminalAppsTests.\(UUID().uuidString)")!)
        manager.currentLanguage = "en"
        XCTAssertEqual(manager.localized("alert.terminalNotSupported"), "Not supported in the terminal")
        manager.currentLanguage = "ru"
        XCTAssertEqual(manager.localized("alert.terminalNotSupported"), "В терминале не поддерживается")
    }
}
