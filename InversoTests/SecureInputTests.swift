import XCTest

@testable import Inverso

@MainActor
final class SecureInputTests: XCTestCase {

    private struct FakeSecureInput: SecureInputDetecting {
        var active: Bool
        func isSecureInputActive() -> Bool { active }
    }

    private final class SpyFeedback: FeedbackProviding {
        private(set) var messages: [String] = []
        private(set) var conversions = 0
        func showConversion(input: String, output: String, layoutCode: String) { conversions += 1 }
        func showMessage(_ message: String) { messages.append(message) }
    }

    private struct SilentSound: SoundPlaying {
        func playConversionSound() {}
    }

    func testHotkeyInSecureFieldTouchesNothing() async throws {
        let suiteName = "SecureInputTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let l10n = LocalizationManager(defaults: defaults)
        l10n.currentLanguage = "en"
        let pasteboard = FakePasteboard(text: "secret")
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "hunter2")
        let selection = FakeSelectedText(text: "hunter2")
        let feedback = SpyFeedback()
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(suiteName).sqlite")
        defer { try? FileManager.default.removeItem(at: logURL) }
        let settings = SettingsManager(defaults: defaults)
        // Every path past the check would log: the AX selection, smart conversion, the log
        settings.loggingEnabled = true

        let coordinator = ConversionCoordinator(
            settingsManager: settings,
            l10n: l10n,
            conversionLogStore: ConversionLogStore(databaseURL: logURL),
            hotkeyManager: HotkeyManager(),
            accessibilityService: AccessibilityService(
                pasteboard: pasteboard, keystrokes: app, selection: selection),
            feedbackProviders: FeedbackProviders(hud: feedback),
            soundPlayer: SilentSound(),
            secureInput: FakeSecureInput(active: true)
        )

        coordinator.convert()
        // A conversion runs in a Task: give one a chance to start before checking
        try await Task.sleep(for: .milliseconds(300))

        XCTAssertEqual(selection.textReads, 0, "the selection may not be read via AX")
        XCTAssertTrue(selection.replacements.isEmpty)
        XCTAssertTrue(selection.rangeWrites.isEmpty)
        XCTAssertTrue(selection.overlayTargets.isEmpty)
        XCTAssertTrue(app.sent.isEmpty, "no keystroke may be sent")
        XCTAssertEqual(pasteboard.changeCount, 0, "the pasteboard must not be touched")
        XCTAssertEqual(pasteboard.text, "secret")
        XCTAssertEqual(feedback.messages, ["Not supported in password fields"])
        XCTAssertEqual(feedback.conversions, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: logURL.path), "nothing may be logged")
    }

    func testHintIsLocalized() throws {
        let suiteName = "SecureInputTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let l10n = LocalizationManager(defaults: defaults)
        l10n.currentLanguage = "ru"
        XCTAssertEqual(l10n.localized("alert.secureFieldNotSupported"), "В полях пароля не поддерживается")
    }
}
