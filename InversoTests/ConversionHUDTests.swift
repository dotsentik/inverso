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
        hud.show(ConversionHUDContent(input: "b", output: "и", layoutCode: "RU"))
        XCTAssertTrue(hud.panel === first, "one panel, text swapped")

        try await Task.sleep(for: .milliseconds(800))
        XCTAssertFalse(first.isVisible)
    }
}
