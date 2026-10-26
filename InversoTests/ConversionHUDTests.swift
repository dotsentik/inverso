import AppKit
import XCTest

@testable import Inverso

@MainActor
final class ConversionHUDTests: XCTestCase {

    private let layouts = [
        KeyboardLayout(id: "com.apple.keylayout.US", localizedName: "U.S.", languageCode: "en"),
        KeyboardLayout(id: "com.apple.keylayout.RussianWin", localizedName: "Russian – PC", languageCode: "ru"),
        KeyboardLayout(id: "com.apple.keylayout.Custom", localizedName: "Custom", languageCode: "unknown"),
        KeyboardLayout(id: "com.apple.keylayout.Ukrainian-PC", localizedName: "Ukrainian", languageCode: "uk-UA"),
    ]

    // MARK: - Content

    func testLayoutCode_FromLanguage() {
        XCTAssertEqual(ConversionHUDContent.layoutCode(for: "com.apple.keylayout.RussianWin", in: layouts), "RU")
        XCTAssertEqual(ConversionHUDContent.layoutCode(for: "com.apple.keylayout.US", in: layouts), "EN")
        XCTAssertEqual(ConversionHUDContent.layoutCode(for: "com.apple.keylayout.Ukrainian-PC", in: layouts), "UK")
    }

    func testLayoutCode_FallsBackToIDWhenLanguageUnknown() {
        XCTAssertEqual(ConversionHUDContent.layoutCode(for: "com.apple.keylayout.Custom", in: layouts), "Custom")
        XCTAssertEqual(ConversionHUDContent.layoutCode(for: "com.example.Greek", in: layouts), "Greek")
        XCTAssertEqual(ConversionHUDContent.layoutCode(for: nil, in: layouts), "")
    }

    func testLongTextIsShortenedInTheMiddle() {
        let long = String(repeating: "a", count: 30) + String(repeating: "b", count: 30)
        let content = ConversionHUDContent(input: long, output: "x", layoutCode: "RU")

        XCTAssertEqual(content.input.count, ConversionHUDContent.maxCharacters)
        XCTAssertTrue(content.input.hasPrefix("aaa"))
        XCTAssertTrue(content.input.hasSuffix("bbb"))
        XCTAssertTrue(content.input.contains("…"))
    }

    func testShortTextAndWhitespace() {
        let content = ConversionHUDContent(input: " ghbdtn\n", output: "привет ", layoutCode: "RU")
        XCTAssertEqual(content.input, "ghbdtn")
        XCTAssertEqual(content.output, "привет")
        XCTAssertEqual(content.spokenText, "ghbdtn → привет, RU")
    }

    func testMessageContent() {
        let content = ConversionHUDContent(message: "Not supported in the terminal")
        XCTAssertEqual(content.message, "Not supported in the terminal")
        XCTAssertEqual(content.spokenText, "Not supported in the terminal")
        XCTAssertNil(ConversionHUDContent(input: "a", output: "ф", layoutCode: "RU").message)
    }

    // MARK: - Background

    func testReduceTransparencyUsesSolidBackground() {
        XCTAssertEqual(HUDBackgroundStyle.current(reduceTransparency: true), .solid)
    }

    func testGlassOnMacOS26_MaterialBefore() {
        let expected: HUDBackgroundStyle
        if #available(macOS 26, *) { expected = .glass } else { expected = .material }
        XCTAssertEqual(HUDBackgroundStyle.current(reduceTransparency: false), expected)
    }

    // MARK: - Placement

    func testFrameIsCenteredBelowMenuBar() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let frame = ConversionHUD.frame(size: NSSize(width: 200, height: 50), on: screen)

        XCTAssertEqual(frame.midX, screen.visibleFrame.midX, accuracy: 1)
        XCTAssertLessThanOrEqual(frame.maxY, screen.visibleFrame.maxY)
        XCTAssertGreaterThan(frame.minY, screen.visibleFrame.midY, "near the top")
    }

    // MARK: - Panel

    func testPanelAndHostingViewAreNilUntilFirstShow() {
        let hud = ConversionHUD()
        XCTAssertNil(hud.panel)
        XCTAssertNil(hud.hostingView)
    }

    func testPanelNeverTakesFocusOrMouse() throws {
        let hud = ConversionHUD()
        hud.show(ConversionHUDContent(input: "ghbdtn", output: "привет", layoutCode: "RU"))
        defer { hud.panel?.orderOut(nil) }

        let panel = try XCTUnwrap(hud.panel)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.isVisible)
        XCTAssertFalse(panel.isKeyWindow)
        XCTAssertGreaterThan(panel.frame.width, 0)
    }

    func testPanelIsReusedAndHidesAfterDuration() async throws {
        let hud = ConversionHUD()
        hud.displayDuration = .milliseconds(50)

        hud.show(ConversionHUDContent(input: "a", output: "ф", layoutCode: "RU"))
        let first = try XCTUnwrap(hud.panel)
        let firstHosting = try XCTUnwrap(hud.hostingView)
        hud.show(ConversionHUDContent(input: "b", output: "и", layoutCode: "RU"))
        XCTAssertTrue(hud.panel === first, "one panel, text swapped")
        XCTAssertTrue(hud.hostingView === firstHosting, "NSHostingView reused via rootView")
        XCTAssertEqual(firstHosting.rootView.content.output, "и")

        try await Task.sleep(for: .milliseconds(800))
        XCTAssertFalse(first.isVisible)
    }

    // MARK: - FeedbackProviding

    func testFeedbackProviders() throws {
        let hud = ConversionHUD()
        defer { hud.panel?.orderOut(nil) }
        let hudProvider: FeedbackProviding = HUDFeedbackProvider(hud: hud)
        hudProvider.showConversion(input: "ghbdtn", output: "привет", layoutCode: "RU")
        XCTAssertEqual(hud.hostingView?.rootView.content.output, "привет")

        hudProvider.showMessage("Terminal hint")
        XCTAssertEqual(hud.hostingView?.rootView.content.message, "Terminal hint")

        var notifiedPair: (String, String)?
        let notificationProvider: FeedbackProviding = NotificationFeedbackProvider { input, output in
            notifiedPair = (input, output)
        }
        notificationProvider.showConversion(input: "ghbdtn", output: "привет", layoutCode: "RU")
        XCTAssertEqual(notifiedPair?.0, "ghbdtn")
        XCTAssertEqual(notifiedPair?.1, "привет")

        var soundPlayed = false
        let soundPlayer: SoundPlaying = SystemSoundPlayer {
            soundPlayed = true
        }
        soundPlayer.playConversionSound()
        XCTAssertTrue(soundPlayed)

        let silentProvider: FeedbackProviding = SilentFeedbackProvider()
        silentProvider.showConversion(input: "a", output: "ф", layoutCode: "RU")
        silentProvider.showMessage("Ignored")

        XCTAssertEqual(SystemSoundPlayer.defaultSoundName, NSSound.Name("word-change"))
    }

    func testConversionSoundIsBundled() {
        XCTAssertNotNil(
            Bundle.main.url(forResource: "word-change", withExtension: "aif"),
            "word-change.aif is not in the app bundle; check Copy Bundle Resources")
        XCTAssertNotNil(NSSound(named: SystemSoundPlayer.defaultSoundName))
    }

    func testHUDFeedbackProviderMemoizesDefaultHUDInstance() throws {
        let provider = HUDFeedbackProvider()
        defer { provider.hud.panel?.orderOut(nil) }

        provider.showConversion(input: "ghbdtn", output: "привет", layoutCode: "RU")
        let firstHUD = provider.hud
        let firstPanel = try XCTUnwrap(firstHUD.panel)

        provider.showMessage("Second message")
        XCTAssertTrue(provider.hud === firstHUD)
        XCTAssertTrue(provider.hud.panel === firstPanel)
    }

    func testDefaultShowMessageIsNoOpForProvidersWithoutMessageUI() {
        @MainActor
        final class RecordingProvider: FeedbackProviding {
            var conversions: [(String, String, String)] = []
            func showConversion(input: String, output: String, layoutCode: String) {
                conversions.append((input, output, layoutCode))
            }
        }

        let custom: FeedbackProviding = RecordingProvider()
        custom.showMessage("Should be ignored by default extension")

        var notified = false
        let notification: FeedbackProviding = NotificationFeedbackProvider { _, _ in
            notified = true
        }
        notification.showMessage("Ignored")
        XCTAssertFalse(notified)
    }

    func testFeedbackProvidersFollowTheSetting() {
        final class Marker: FeedbackProviding {
            func showConversion(input: String, output: String, layoutCode: String) {}
        }
        let hud = Marker()
        let notification = Marker()
        let silent = Marker()
        let providers = FeedbackProviders(hud: hud, notification: notification, silent: silent)

        XCTAssertTrue(providers.provider(for: .hud) as AnyObject === hud)
        XCTAssertTrue(providers.provider(for: .notification) as AnyObject === notification)
        XCTAssertTrue(providers.provider(for: .none) as AnyObject === silent)
    }
}
