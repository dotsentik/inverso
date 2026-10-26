import AppKit
import ApplicationServices

/// Reads the text to convert and puts the converted text back: through the Accessibility API
/// where the app supports it, otherwise through ⌘C / ⌘V with the user's pasteboard restored.
@MainActor
final class AccessibilityService {

    /// Delays of the copy → convert → paste chain. None of them blocks the main thread.
    struct Timing {
        /// How long to wait for the target app to put the selection on the pasteboard after ⌘C.
        var copyTimeout: Duration = .milliseconds(300)
        /// How often to check NSPasteboard.changeCount (and the AX selection) while waiting.
        var pollInterval: Duration = .milliseconds(10)
        /// Pause after a selection keystroke. Selection changes are not observable via the pasteboard.
        var selectionSettle: Duration = .milliseconds(50)
        /// After a selection keystroke, how long AX may keep reporting an empty selection
        /// before we conclude there is nothing to select.
        var selectionTimeout: Duration = .milliseconds(200)
        /// Pause after ⌘V before restoring the pasteboard. Reading the pasteboard does not
        /// change changeCount, so there is no signal that the target app has pasted.
        var pasteSettle: Duration = .milliseconds(300)
    }

    private let pasteboard: PasteboardAccess
    private let keystrokes: KeystrokeSender
    private let selection: SelectedTextAccess
    private let timing: Timing

    init(
        pasteboard: PasteboardAccess = SystemPasteboard(),
        keystrokes: KeystrokeSender = CGEventKeystrokeSender(),
        selection: SelectedTextAccess = AXSelectedTextAccess(),
        timing: Timing = Timing()
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.selection = selection
        self.timing = timing
    }

    // MARK: - Permission

    static var hasAccessibilityPermission: Bool {
        let trusted = AXIsProcessTrusted()
        Log.accessibility.debug(
            "AXIsProcessTrusted() = \(trusted), bundle = \(Bundle.main.bundlePath, privacy: .public)")
        return trusted
    }

    /// Shows the system prompt that leads to System Settings.
    static func requestAccessibilityPermission() {
        // Literal value of kAXTrustedCheckOptionPrompt: the C global is a mutable var, which Swift 6 rejects.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        Log.accessibility.info("AXIsProcessTrustedWithOptions(prompt=true) = \(trusted)")
    }

    // MARK: - Replacing Text

    // Each method takes the focus mode resolved by `AppRuleRegistry` for this conversion.
    // In a terminal they do nothing and return false.

    /// Converts the current selection. Returns false if nothing was selected or converted.
    func replaceSelection(
        in focusMode: AppRuleRegistry.FocusMode,
        using converter: (String) -> String?
    ) async -> Bool {
        await copyConvertPaste(select: nil, focusMode: focusMode, label: "replaceSelection", converter: converter)
    }

    /// Selects from the cursor to the line start (⌘⇧←) and converts it. The converter decides
    /// which part to convert and returns the whole replacement line.
    func replaceLineBeforeCursor(
        in focusMode: AppRuleRegistry.FocusMode,
        using converter: (String) -> String?
    ) async -> Bool {
        await copyConvertPaste(
            select: .selectToLineStart, focusMode: focusMode, label: "replaceLineBeforeCursor", converter: converter)
    }

    /// Selects the word before the cursor (⇧⌥←) and converts it.
    func replaceLastWord(
        in focusMode: AppRuleRegistry.FocusMode,
        using converter: (String) -> String?
    ) async -> Bool {
        await copyConvertPaste(
            select: .selectWordLeft, focusMode: focusMode, label: "replaceLastWord", converter: converter)
    }

    /// Reads the selection via AX (kAXSelectedTextAttribute) or, failing that, ⌘C; replaces it
    /// via AX or, failing that, ⌘V. Clipboard-only apps (Electron) skip AX text access.
    /// In Spotlight and Open/Save panels the replacement is typed instead: they are not the
    /// frontmost app, and AX writes there are unreliable. There the text before the cursor is
    /// selected through AX (kAXSelectedTextRangeAttribute), keystrokes are the fallback, and
    /// all keystrokes are routed to the key window rather than the frontmost app.
    /// The pasteboard is saved before our first write to it and restored afterwards.
    /// - Parameter select: keystroke that selects the text first; on failure the selection
    ///   is restored (AX) or collapsed with → so the cursor stays where the user left it.
    private func copyConvertPaste(
        select: Keystroke?,
        focusMode: AppRuleRegistry.FocusMode,
        label: String,
        converter: (String) -> String?
    ) async -> Bool {
        guard let strategy = TextAccessStrategy.resolve(for: focusMode) else {
            Log.focus.debug("\(label, privacy: .public): terminal has the focus, no text access")
            return false
        }
        var savedContents: PasteboardSnapshot?
        var ownChangeCount = 0
        let keystrokes = strategy.routesKeystrokesToKeyWindow ? self.keystrokes.routedToKeyWindow() : self.keystrokes
        let selection = self.selection.focused(onOverlay: focusMode.overlayPID)
        if strategy == .overlay {
            Log.focus.debug("\(label, privacy: .public): Spotlight / Open-Save panel has the focus")
        } else if strategy.readMethod == .pasteboardOnly {
            Log.accessibility.debug("\(label, privacy: .public): clipboard-only app, skipping AX text access")
        }

        switch await prepareSelection(
            select: select, strategy: strategy, selection: selection, keystrokes: keystrokes, label: label)
        {
        case .abort:
            return false
        case .ready(let selectionToRestore):
            // With nothing selected, ⌘C in CodeMirror (Obsidian) and VS Code copies the whole
            // current line, and ⌘V would then insert the converted line at the cursor instead of
            // replacing anything. So don't copy when AX reports an empty selection.
            if await selectionIsEmpty(selection, afterSelecting: select != nil) {
                Log.accessibility.debug("\(label, privacy: .public): AX reports an empty selection, nothing to copy")
                return false
            }

            let selectedText = await readSelectedText(
                strategy: strategy,
                selection: selection,
                keystrokes: keystrokes,
                label: label,
                savedContents: &savedContents,
                ownChangeCount: &ownChangeCount
            )
            guard let selectedText else {
                if select != nil { undoSelection(selectionToRestore, selection: selection, keystrokes: keystrokes) }
                if let savedContents { restoreIfUntouched(savedContents, ownChangeCount: ownChangeCount) }
                return false
            }

            Log.accessibility.debug(
                "\(label, privacy: .public): read = '\(selectedText, privacy: .private)' (len=\(selectedText.count))")

            guard let convertedText = converter(selectedText) else {
                Log.accessibility.debug("\(label, privacy: .public): converter returned nil")
                if select != nil { undoSelection(selectionToRestore, selection: selection, keystrokes: keystrokes) }
                if let savedContents { restoreIfUntouched(savedContents, ownChangeCount: ownChangeCount) }
                return false
            }

            await writeConvertedText(
                convertedText,
                strategy: strategy,
                selection: selection,
                keystrokes: keystrokes,
                label: label,
                savedContents: savedContents,
                ownChangeCount: ownChangeCount
            )
            return true
        }
    }

    // MARK: - Strategy Execution

    private enum SelectionPreparation {
        case ready(restoreRange: NSRange?)
        case abort
    }

    private func prepareSelection(
        select: Keystroke?,
        strategy: TextAccessStrategy,
        selection: SelectedTextAccess,
        keystrokes: KeystrokeSender,
        label: String
    ) async -> SelectionPreparation {
        var selectionToRestore: NSRange?
        if strategy.selectionMethod == .axRangeWithKeystrokeFallback, let state = selection.textState() {
            let (action, isInlineCompletion) = OverlayTextSelection.action(for: select, in: state)
            if isInlineCompletion {
                Log.focus.debug("\(label, privacy: .public): inline completion selected, converting the typed text")
            }
            switch action {
            case .abort:
                if select != nil {
                    Log.focus.debug("\(label, privacy: .public): nothing before the cursor")
                }
                return .abort
            case .selectRange(let range, let restore):
                if selection.setSelectedRange(range) {
                    Log.focus.debug("\(label, privacy: .public): selected via AX range")
                    selectionToRestore = restore
                }
            case .keepSelection:
                break
            }
        }

        if let select, selectionToRestore == nil {
            Log.accessibility.debug("\(label, privacy: .public): selecting with keys")
            keystrokes.send(select)
            if timing.selectionSettle != .zero {
                do {
                    try await Task.sleep(for: timing.selectionSettle)
                } catch {
                    return .abort
                }
            }
        }
        return .ready(restoreRange: selectionToRestore)
    }

    private func readSelectedText(
        strategy: TextAccessStrategy,
        selection: SelectedTextAccess,
        keystrokes: KeystrokeSender,
        label: String,
        savedContents: inout PasteboardSnapshot?,
        ownChangeCount: inout Int
    ) async -> String? {
        if strategy.readMethod == .axWithPasteboardFallback, let text = selection.selectedText() {
            return text
        }
        savedContents = pasteboard.snapshot()
        let clearedCount = pasteboard.clear()
        keystrokes.send(.copy)
        let copied = await waitForPasteboardChange(from: clearedCount, timeout: timing.copyTimeout)
        // Whatever is on the pasteboard now was caused by our clear and ⌘C.
        ownChangeCount = pasteboard.changeCount
        if copied, let text = pasteboard.string(), !text.isEmpty {
            return text
        }
        Log.accessibility.debug(
            "\(label, privacy: .public): no text on pasteboard after ⌘C (changed=\(copied))")
        return nil
    }

    private func writeConvertedText(
        _ convertedText: String,
        strategy: TextAccessStrategy,
        selection: SelectedTextAccess,
        keystrokes: KeystrokeSender,
        label: String,
        savedContents: PasteboardSnapshot?,
        ownChangeCount: Int
    ) async {
        switch strategy.replaceMethod {
        case .typing:
            Log.focus.debug("\(label, privacy: .public): replace path = typing")
            keystrokes.send(.typeText(convertedText))
            if let savedContents { restoreIfUntouched(savedContents, ownChangeCount: ownChangeCount) }

        case .axWithPasteboardFallback:
            // Accessibility first. Fall back only if the text is provably unchanged,
            // otherwise the converted text could end up inserted twice.
            let axResult = await selection.replaceSelectedText(with: convertedText)
            if axResult != .unchanged {
                Log.accessibility.debug(
                    "\(label, privacy: .public): replaced via AX (\(String(describing: axResult), privacy: .public))")
                if let savedContents { restoreIfUntouched(savedContents, ownChangeCount: ownChangeCount) }
                return
            }
            await pasteConvertedText(
                convertedText,
                keystrokes: keystrokes,
                label: label,
                savedContents: savedContents
            )

        case .pasteboardOnly:
            await pasteConvertedText(
                convertedText,
                keystrokes: keystrokes,
                label: label,
                savedContents: savedContents
            )
        }
    }

    private func pasteConvertedText(
        _ convertedText: String,
        keystrokes: KeystrokeSender,
        label: String,
        savedContents: PasteboardSnapshot?
    ) async {
        Log.accessibility.debug("\(label, privacy: .public): pasting = '\(convertedText, privacy: .private)'")

        let contentsToRestore = savedContents ?? pasteboard.snapshot()
        let ownChangeCount = pasteboard.writeTemporary(convertedText)
        keystrokes.send(.paste)

        if timing.pasteSettle != .zero {
            try? await Task.sleep(for: timing.pasteSettle)
        }
        restoreIfUntouched(contentsToRestore, ownChangeCount: ownChangeCount)
    }

    /// Puts the selection back as it was before we selected the text to convert.
    private func undoSelection(_ range: NSRange?, selection: SelectedTextAccess, keystrokes: KeystrokeSender) {
        if let range, selection.setSelectedRange(range) { return }
        keystrokes.send(.rightArrow)
    }

    // MARK: - Waiting

    /// True only if AX positively reports an empty selection; unknown counts as not empty.
    /// After a selection keystroke, waits for the app to apply it (Electron updates AX lazily).
    private func selectionIsEmpty(_ selection: SelectedTextAccess, afterSelecting: Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timing.selectionTimeout)
        while !Task.isCancelled {
            guard let length = selection.selectedLength() else { return false }
            if length > 0 { return false }
            guard afterSelecting, clock.now < deadline else { return true }
            do {
                try await Task.sleep(for: timing.pollInterval)
            } catch {
                return false
            }
        }
        return false
    }

    /// Polls changeCount until it differs from `count`. Returns false on timeout or cancellation.
    func waitForPasteboardChange(from count: Int, timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while pasteboard.changeCount == count {
            guard !Task.isCancelled, clock.now < deadline else { return false }
            do {
                try await Task.sleep(for: timing.pollInterval)
            } catch {
                return false
            }
        }
        return !Task.isCancelled
    }

    // MARK: - Pasteboard

    /// Restores the user's contents unless someone wrote to the pasteboard after our last
    /// write: then that is the user's fresh copy, and restoring would destroy it.
    private func restoreIfUntouched(_ savedContents: PasteboardSnapshot, ownChangeCount: Int) {
        guard pasteboard.changeCount == ownChangeCount else {
            Log.accessibility.info("Pasteboard changed by another app since our write, not restoring")
            return
        }
        pasteboard.restore(savedContents)
    }
}
