import Cocoa

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

    /// What one conversion changed: only the converted part, never the kept rest of the line.
    /// Fields stay nil until the converter produces a result.
    private struct Capture {
        var input: String?
        var output: String?
        var sourceLayoutID: String?
        var targetLayoutID: String?

        mutating func record(_ result: TextConverter.ConversionResult) {
            input = result.originalSegment
            output = result.convertedSegment
            sourceLayoutID = result.sourceLayoutID
            targetLayoutID = result.targetLayoutID
        }
    }

    private let settingsManager: SettingsManager
    private let l10n: LocalizationManager
    private let logStoreProvider: @MainActor () -> ConversionLogStore
    private let hotkeyManager: HotkeyManager
    private lazy var accessibilityService: AccessibilityService = accessibilityServiceFactory()
    private let accessibilityServiceFactory: @MainActor () -> AccessibilityService
    private let feedbackProviders: FeedbackProviders
    private let soundPlayer: SoundPlaying
    private let secureInput: SecureInputDetecting
    private lazy var textConverter = TextConverter(
        preferences: settingsManager,
        mapProvider: LayoutMaps.shared,
        currentLayoutID: { KeyboardLayoutDetector.currentLayout()?.id },
        wordValidator: SpellCheckerWordValidator()
    )

    init(
        settingsManager: SettingsManager,
        l10n: LocalizationManager,
        conversionLogStore: @autoclosure @escaping @MainActor () -> ConversionLogStore,
        hotkeyManager: HotkeyManager,
        accessibilityService: @autoclosure @escaping @MainActor () -> AccessibilityService,
        feedbackProviders: FeedbackProviders,
        soundPlayer: SoundPlaying,
        secureInput: SecureInputDetecting = SecureInputDetector()
    ) {
        self.settingsManager = settingsManager
        self.l10n = l10n
        self.logStoreProvider = conversionLogStore
        self.hotkeyManager = hotkeyManager
        self.accessibilityServiceFactory = accessibilityService
        self.feedbackProviders = feedbackProviders
        self.soundPlayer = soundPlayer
        self.secureInput = secureInput
    }

    /// The chain drives the shared pasteboard, so only one conversion may run at a time.
    private var conversionInProgress = false
    /// The missing-permission tip is logged once per session.
    private var hasLoggedPermissionTip = false

    // MARK: - Hotkey

    /// While the shortcut recorder listens, the hotkey is off and setting changes wait for it to end.
    private var isHotkeyPaused = false

    /// Registers the hotkey and re-registers it whenever its settings change.
    func start() {
        registerHotkey()
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(hotkeySettingsDidChange), name: .hotkeySettingsChanged, object: nil)
        center.addObserver(
            self, selector: #selector(hotkeyRecordingDidStart), name: .hotkeyRecordingStarted, object: nil)
        center.addObserver(
            self, selector: #selector(hotkeyRecordingDidEnd), name: .hotkeyRecordingEnded, object: nil)
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
        guard !isHotkeyPaused else { return }
        registerHotkey()
    }

    @objc private func hotkeyRecordingDidStart() {
        isHotkeyPaused = true
        hotkeyManager.unregister()
    }

    @objc private func hotkeyRecordingDidEnd() {
        isHotkeyPaused = false
        registerHotkey()
    }

    // MARK: - Conversion

    func convert() {
        guard !conversionInProgress else {
            Log.app.debug("Conversion already in progress, ignoring trigger")
            return
        }
        // Password fields: no keystrokes, no pasteboard, no logging; only the hint.
        if secureInput.isSecureInputActive() {
            feedbackProviders.provider(for: .hud).showMessage(l10n.localized("alert.secureFieldNotSupported"))
            return
        }
        // One focus decision per conversion; every text access step below uses it.
        let focusMode = AppRuleRegistry.currentFocusMode()
        // Terminals: no keystrokes, no pasteboard, no text changes; only the hint.
        if focusMode == .terminal {
            Log.app.info("Terminal has the focus, conversion is not supported")
            let hint = l10n.localized("alert.terminalNotSupported")
            feedbackProviders.provider(for: .hud).showMessage(hint)
            return
        }
        conversionInProgress = true
        Task {
            await runConversion(in: focusMode)
            conversionInProgress = false
        }
    }

    private func runConversion(in focusMode: AppRuleRegistry.FocusMode) async {
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
        let outcome = await accessibilityService.replaceSelection(in: focusMode) { [weak self] text in
            Log.app.debug("replaceSelection got text: '\(text, privacy: .private)' (len=\(text.count))")
            guard let result = self?.textConverter.convert(text) else {
                Log.app.debug("convert returned nil")
                return nil
            }
            capture.record(result)
            Log.app.debug("convert returned: '\(result.text, privacy: .private)'")
            return result.text
        }

        switch outcome {
        case .replaced:
            Log.app.info("Direct conversion succeeded")
            finishConversion(capture, mode: .direct)
        case .nothingSelected:
            Log.app.debug("No selected text, trying smart conversion")
            await runSmartConversion(in: focusMode)
        case .notConverted:
            // A selection exists: selecting more text around it would touch what the user did not select.
            Log.app.debug("Selected text was not converted; smart conversion skipped")
        }
    }

    /// Without a selection, the Smart Conversion mode decides what to convert.
    private func runSmartConversion(in focusMode: AppRuleRegistry.FocusMode) async {
        let mode = settingsManager.smartConversionMode
        Log.app.debug("runSmartConversion() mode=\(mode.rawValue)")

        switch mode {
        case .disabled:
            Log.app.debug("Smart conversion is disabled")
        case .lastWord:
            await convertLastWord(in: focusMode)
        case .greedyLine:
            await convertLineGreedily(in: focusMode)
        }
    }

    /// Selects one word left and converts it if it looks like the wrong layout.
    private func convertLastWord(in focusMode: AppRuleRegistry.FocusMode) async {
        var capture = Capture()
        let outcome = await accessibilityService.replaceLastWord(in: focusMode) { [weak self] text in
            guard let self else { return nil }
            Log.app.debug("lastWord got: '\(text, privacy: .private)'")
            guard textConverter.looksLikeWrongLayout(text) else { return nil }
            guard let result = textConverter.convert(text) else { return nil }
            capture.record(result)
            return result.text
        }
        if outcome == .replaced {
            finishConversion(capture, mode: .lastWord)
        }
    }

    /// Selects to the line start and converts the wrong-layout tail of the line.
    private func convertLineGreedily(in focusMode: AppRuleRegistry.FocusMode) async {
        var capture = Capture()
        let outcome = await accessibilityService.replaceLineBeforeCursor(in: focusMode) { [weak self] lineText in
            guard let self else { return nil }
            Log.app.debug("greedyLine got line: '\(lineText, privacy: .private)' (len=\(lineText.count))")
            guard let result = textConverter.convertLineGreedily(lineText) else { return nil }
            capture.record(result)
            return result.text
        }
        if outcome == .replaced {
            finishConversion(capture, mode: .greedyLine)
        }
    }

    private func finishConversion(_ capture: Capture, mode: Mode) {
        settingsManager.incrementConversionCount()
        logConversion(capture, mode: mode)
        switchLayoutIfNeeded(for: capture)
        playSoundIfEnabled()
        showFeedback(for: capture)
    }

    // MARK: - Conversion Log

    private func logConversion(_ capture: Capture, mode: Mode) {
        guard settingsManager.loggingEnabled else { return }
        guard let input = capture.input, let output = capture.output else { return }

        let store = logStoreProvider()
        store.log(
            inputText: input,
            outputText: output,
            sourceLayout: capture.sourceLayoutID ?? "unknown",
            targetLayout: capture.targetLayoutID ?? "unknown",
            conversionMode: mode.rawValue,
            trimTo: settingsManager.logMaxEntries
        )
    }

    // MARK: - Layout Switch

    /// Switches the system keyboard layout to the target, as the Layout Switch mode says.
    private func switchLayoutIfNeeded(for capture: Capture) {
        guard let targetLayoutID = capture.targetLayoutID,
            let input = capture.input, let output = capture.output,
            settingsManager.layoutSwitchMode.shouldSwitchLayout(original: input, converted: output)
        else { return }
        KeyboardLayoutDetector.switchLayout(to: targetLayoutID)
    }

    // MARK: - Feedback

    static func requestNotificationAuthorization() {
        NotificationFeedbackProvider.requestAuthorization()
    }

    private func playSoundIfEnabled() {
        guard settingsManager.playSounds else { return }
        soundPlayer.playConversionSound()
    }

    /// Shows the HUD or a notification about the result, as configured.
    private func showFeedback(for capture: Capture) {
        guard let input = capture.input, let output = capture.output else { return }
        let code = ConversionHUDContent.layoutCode(for: capture.targetLayoutID, in: settingsManager.layoutOrder)
        let provider = feedbackProviders.provider(for: settingsManager.conversionFeedback)
        provider.showConversion(input: input, output: output, layoutCode: code)
    }
}
