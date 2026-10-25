import Cocoa
import UserNotifications

/// Runs a conversion when the hotkey fires: converts the selection or, without one, the text
/// chosen by the Smart Conversion mode; then logs it, switches the layout and gives feedback.
@MainActor
final class ConversionCoordinator {

    /// How the text to convert was picked; stored in the conversion log.
    private enum Mode: String {
        case direct
        case lastWord
        case greedyLine
    }

    /// What one conversion read and produced. Fields stay nil until the converter runs.
    private struct Capture {
        var input: String?
        var output: String?
        var targetLayoutID: String?
    }

    private let settingsManager = SettingsManager.shared
    private let conversionLogStore = ConversionLogStore.shared
    private let hotkeyManager = HotkeyManager()
    private let accessibilityService = AccessibilityService()
    private lazy var textConverter = TextConverter(settingsManager: settingsManager)

    /// The chain drives the shared pasteboard, so only one conversion may run at a time.
    private var conversionInProgress = false
    /// The missing-permission tip is logged once per session.
    private var hasLoggedPermissionTip = false

    // MARK: - Hotkey

    /// Registers the hotkey and re-registers it whenever its settings change.
    func start() {
        registerHotkey()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(hotkeySettingsDidChange),
            name: .hotkeySettingsChanged,
            object: nil
        )
    }

    private func registerHotkey() {
        let action: HotkeyManager.Action = { [weak self] in
            Task { @MainActor in
                self?.convert()
            }
        }
        if settingsManager.useDoubleShift {
            hotkeyManager.registerDoubleShift(action: action)
        } else {
            hotkeyManager.register(
                keyCode: settingsManager.hotkeyKeyCode,
                modifiers: settingsManager.hotkeyModifierFlags,
                action: action
            )
        }
    }

    @objc private func hotkeySettingsDidChange() {
        registerHotkey()
    }

    // MARK: - Conversion

    func convert() {
        guard !conversionInProgress else {
            Log.app.debug("Conversion already in progress, ignoring trigger")
            return
        }
        // Terminals: no keystrokes, no pasteboard, no text changes; only the hint.
        if AppRuleRegistry.isTerminalFocused() {
            Log.app.info("Terminal has the focus, conversion is not supported")
            let hint = LocalizationManager.shared.localized("alert.terminalNotSupported")
            ConversionHUD.shared.show(ConversionHUDContent(message: hint))
            return
        }
        conversionInProgress = true
        Task {
            await runConversion()
            conversionInProgress = false
        }
    }

    private func runConversion() async {
        let hasPermission = AccessibilityService.hasAccessibilityPermission
        Log.app.debug("convert() called, hasAccessibilityPermission=\(hasPermission)")

        if !hasPermission {
            Log.app.notice(
                "AXIsProcessTrusted=false. Will attempt conversion anyway (CGEvent may work with Input Monitoring).")
            if !hasLoggedPermissionTip {
                hasLoggedPermissionTip = true
                Log.app.notice(
                    "TIP: If conversion doesn't work, remove the app from Accessibility list in System Settings and re-add it. Also check Input Monitoring."
                )
            }
        }

        var capture = Capture()
        let success = await accessibilityService.replaceSelection { [weak self] text in
            Log.app.debug("replaceSelection got text: '\(text, privacy: .private)' (len=\(text.count))")
            capture.input = text
            guard let result = self?.textConverter.convert(text) else {
                Log.app.debug("convert returned nil")
                return nil
            }
            capture.output = result.text
            capture.targetLayoutID = result.targetLayoutID
            Log.app.debug("convert returned: '\(result.text, privacy: .private)'")
            return result.text
        }

        if success {
            Log.app.info("Direct conversion succeeded")
            finishConversion(capture, mode: .direct)
        } else {
            Log.app.debug("No selected text, trying smart conversion")
            await runSmartConversion()
        }
    }

    /// Without a selection, the Smart Conversion mode decides what to convert.
    private func runSmartConversion() async {
        let mode = settingsManager.smartConversionMode
        Log.app.debug("runSmartConversion() mode=\(mode.rawValue)")

        switch mode {
        case .disabled:
            Log.app.debug("Smart conversion is disabled")
        case .lastWord:
            await convertLastWord()
        case .greedyLine:
            await convertLineGreedily()
        }
    }

    /// Selects one word left and converts it if it looks like the wrong layout.
    private func convertLastWord() async {
        var capture = Capture()
        let success = await accessibilityService.replaceLastWord { [weak self] text in
            guard let self else { return nil }
            Log.app.debug("lastWord got: '\(text, privacy: .private)'")
            guard textConverter.looksLikeWrongLayout(text) else { return nil }
            capture.input = text
            guard let result = textConverter.convert(text) else { return nil }
            capture.output = result.text
            capture.targetLayoutID = result.targetLayoutID
            return result.text
        }
        if success {
            finishConversion(capture, mode: .lastWord)
        }
    }

    /// Selects to the line start and converts the wrong-layout tail of the line.
    private func convertLineGreedily() async {
        var capture = Capture()
        let success = await accessibilityService.replaceLineBeforeCursor { [weak self] lineText in
            guard let self else { return nil }
            Log.app.debug("greedyLine got line: '\(lineText, privacy: .private)' (len=\(lineText.count))")
            capture.input = lineText
            let result = textConverter.convertLineGreedily(lineText)
            capture.output = result?.text
            capture.targetLayoutID = result?.targetLayoutID
            return result?.text
        }
        if success {
            finishConversion(capture, mode: .greedyLine)
        }
    }

    private func finishConversion(_ capture: Capture, mode: Mode) {
        settingsManager.incrementConversionCount()
        logConversion(capture, mode: mode)
        switchLayoutIfNeeded(targetLayoutID: capture.targetLayoutID)
        playSoundIfEnabled()
        showFeedback(for: capture)
    }

    // MARK: - Conversion Log

    private func logConversion(_ capture: Capture, mode: Mode) {
        guard settingsManager.loggingEnabled else { return }
        guard let input = capture.input, let output = capture.output else { return }

        let layouts = settingsManager.enabledLayouts
        let sourceLayout =
            LayoutMapper.detectSourceLayout(text: input, candidateLayouts: layouts.map(\.id)) ?? "unknown"
        let targetLayout = layouts.first(where: { $0.id != sourceLayout })?.id ?? "unknown"

        conversionLogStore.log(
            inputText: input,
            outputText: output,
            sourceLayout: sourceLayout,
            targetLayout: targetLayout,
            conversionMode: mode.rawValue
        )

        let maxEntries = settingsManager.logMaxEntries
        if maxEntries > 0 {
            conversionLogStore.trim(toMaxEntries: maxEntries)
        }
    }

    // MARK: - Layout Switch

    /// Switches the system keyboard layout to the target, as configured.
    /// Every mode switches here: this is only called after a conversion took place.
    private func switchLayoutIfNeeded(targetLayoutID: String?) {
        guard let targetLayoutID else { return }
        switch settingsManager.layoutSwitchMode {
        case .always, .ifLastWordConverted, .ifAnyWordConverted:
            KeyboardLayoutDetector.switchLayout(to: targetLayoutID)
        }
    }

    // MARK: - Feedback

    static func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func playSoundIfEnabled() {
        if settingsManager.playSounds {
            NSSound(named: .init("Tink"))?.play()
        }
    }

    /// Shows the HUD or a notification about the result, as configured.
    private func showFeedback(for capture: Capture) {
        guard let input = capture.input, let output = capture.output else { return }
        switch settingsManager.conversionFeedback {
        case .none:
            return
        case .hud:
            let code = ConversionHUDContent.layoutCode(for: capture.targetLayoutID, in: settingsManager.layoutOrder)
            ConversionHUD.shared.show(ConversionHUDContent(input: input, output: output, layoutCode: code))
        case .notification:
            showNotification(input: input, output: output)
        }
    }

    private func showNotification(input: String, output: String) {
        let content = UNMutableNotificationContent()
        content.title = "Inverso"
        content.body = "\(input) → \(output)"
        content.sound = nil  // The sound is a separate setting, played by playSoundIfEnabled()

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("Failed to show notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
