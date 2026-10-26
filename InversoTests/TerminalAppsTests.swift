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
        XCTAssertEqual(AppRuleRegistry.focusMode(frontmostBundleID: "com.apple.Terminal"), .terminal)
    }

    /// Spotlight or an Open/Save panel above a terminal takes the keyboard focus.
    func testOverlayAboveTerminalHasFocus() {
        XCTAssertEqual(
            AppRuleRegistry.focusMode(frontmostBundleID: "com.apple.Terminal", overlayPID: 4242), .overlay(4242))
    }

    func testOtherAppInFront() {
        XCTAssertEqual(AppRuleRegistry.focusMode(frontmostBundleID: "com.apple.TextEdit"), .standard)
    }

    @MainActor
    func testHintIsLocalized() throws {
        let suiteName = "TerminalAppsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let manager = LocalizationManager(defaults: defaults)
        manager.currentLanguage = "en"
        XCTAssertEqual(manager.localized("alert.terminalNotSupported"), "Not supported in the terminal")
        manager.currentLanguage = "ru"
        XCTAssertEqual(manager.localized("alert.terminalNotSupported"), "В терминале не поддерживается")
    }

    func testAppRuleRegistryFocusModePrecedence() throws {
        // Active overlay always wins over terminal, clipboard-only, and standard apps
        XCTAssertEqual(
            AppRuleRegistry.focusMode(frontmostBundleID: "com.apple.Terminal", overlayPID: 4242),
            .overlay(4242)
        )
        XCTAssertEqual(
            AppRuleRegistry.focusMode(frontmostBundleID: "com.microsoft.VSCode", overlayPID: 1001),
            .overlay(1001)
        )
        XCTAssertEqual(
            AppRuleRegistry.focusMode(frontmostBundleID: "com.apple.TextEdit", overlayPID: 99),
            .overlay(99)
        )

        // Without an overlay, terminal apps resolve to .terminal
        for bundleID in TerminalApps.bundleIDs {
            XCTAssertEqual(
                AppRuleRegistry.focusMode(frontmostBundleID: bundleID, overlayPID: nil),
                .terminal,
                bundleID
            )
        }

        // Clipboard-only bundle IDs and Electron bundles resolve to .clipboardOnly
        for bundleID in ClipboardOnlyApps.bundleIDs {
            XCTAssertEqual(
                AppRuleRegistry.focusMode(frontmostBundleID: bundleID, overlayPID: nil),
                .clipboardOnly,
                bundleID
            )
        }

        let electronBundle = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppRuleElectron-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: electronBundle) }
        try FileManager.default.createDirectory(
            at: electronBundle.appendingPathComponent("Contents/Frameworks/Electron Framework.framework"),
            withIntermediateDirectories: true
        )
        XCTAssertEqual(
            AppRuleRegistry.focusMode(
                frontmostBundleID: "com.example.CustomElectron",
                frontmostBundleURL: electronBundle,
                overlayPID: nil
            ),
            .clipboardOnly
        )

        // Regular apps and nil bundle ID resolve to .standard
        XCTAssertEqual(
            AppRuleRegistry.focusMode(frontmostBundleID: "com.apple.TextEdit", overlayPID: nil),
            .standard
        )
        XCTAssertEqual(
            AppRuleRegistry.focusMode(frontmostBundleID: nil, overlayPID: nil),
            .standard
        )
    }

    func testTextAccessStrategyResolveForFocusMode() {
        XCTAssertNil(TextAccessStrategy.resolve(for: .terminal))
        XCTAssertEqual(TextAccessStrategy.resolve(for: .overlay(1234)), .overlay)
        XCTAssertEqual(TextAccessStrategy.resolve(for: .clipboardOnly), .clipboardOnly)
        XCTAssertEqual(TextAccessStrategy.resolve(for: .standard), .standard)
    }
}
