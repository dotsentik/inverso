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
    /// True if the frontmost app must not be read or written via AX text attributes.
    private let isClipboardOnlyApp: @MainActor () -> Bool
    /// True if Spotlight or an Open/Save panel has the keyboard focus (see KeyboardFocusOwner).
    private let isOverlayFocused: @MainActor () -> Bool

    init(
        pasteboard: PasteboardAccess = SystemPasteboard(),
        keystrokes: KeystrokeSender = CGEventKeystrokeSender(),
        selection: SelectedTextAccess = AXSelectedTextAccess(),
        timing: Timing = Timing(),
        isClipboardOnlyApp: @escaping @MainActor () -> Bool = AppRuleRegistry.isClipboardOnlyFrontmost,
        isOverlayFocused: @escaping @MainActor () -> Bool = { AppRuleRegistry.overlayPID() != nil }
    ) {
        self.pasteboard = pasteboard
        self.keystrokes = keystrokes
        self.selection = selection
        self.timing = timing
        self.isClipboardOnlyApp = isClipboardOnlyApp
        self.isOverlayFocused = isOverlayFocused
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

    /// Converts the current selection. Returns false if nothing was selected or converted.
    func replaceSelection(using converter: (String) -> String?) async -> Bool {
        await copyConvertPaste(select: nil, label: "replaceSelection", converter: converter)
    }

    /// Selects from the cursor to the line start (⌘⇧←) and converts it. The converter decides
    /// which part to convert and returns the whole replacement line.
    func replaceLineBeforeCursor(using converter: (String) -> String?) async -> Bool {
        await copyConvertPaste(select: .selectToLineStart, label: "replaceLineBeforeCursor", converter: converter)
    }

    /// Selects the word before the cursor (⇧⌥←) and converts it.
    func replaceLastWord(using converter: (String) -> String?) async -> Bool {
        await copyConvertPaste(select: .selectWordLeft, label: "replaceLastWord", converter: converter)
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
        label: String,
        converter: (String) -> String?
    ) async -> Bool {
        var savedContents: PasteboardSnapshot?
        var ownChangeCount = 0
        // The clipboard-only check looks at the frontmost app, which is not the one with the
        // focus while an overlay is open.
        let overlayFocused = isOverlayFocused()
        let useAX = overlayFocused || !isClipboardOnlyApp()
        let keystrokes = overlayFocused ? self.keystrokes.routedToKeyWindow() : self.keystrokes
        if overlayFocused {
            Log.focus.debug("\(label, privacy: .public): Spotlight / Open-Save panel has the focus")
        } else if !useAX {
            Log.accessibility.debug("\(label, privacy: .public): clipboard-only app, skipping AX text access")
        }

        // Overlays: the selection the text is restored to if nothing gets converted.
        var selectionToRestore: NSRange?
        if overlayFocused, let state = selection.textState() {
            let completion = OverlayTextSelection.isInlineCompletion(state)
            if completion {
                Log.focus.debug("\(label, privacy: .public): inline completion selected, converting the typed text")
            }
            if select == nil, completion {
                // Not the user's selection: Smart Conversion converts the text before it.
                return false
            }
            if let select {
                guard let range = OverlayTextSelection.rangeBeforeCursor(select, in: state) else {
                    Log.focus.debug("\(label, privacy: .public): nothing before the cursor")
                    return false
                }
                if selection.setSelectedRange(range) {
                    Log.focus.debug("\(label, privacy: .public): selected via AX range")
                    selectionToRestore = state.selectedRange
                }
            }
        }

        if let select, selectionToRestore == nil {
            Log.accessibility.debug("\(label, privacy: .public): selecting with keys")
            keystrokes.send(select)
            try? await Task.sleep(for: timing.selectionSettle)
        }

        // With nothing selected, ⌘C in CodeMirror (Obsidian) and VS Code copies the whole
        // current line, and ⌘V would then insert the converted line at the cursor instead of
        // replacing anything. So don't copy when AX reports an empty selection.
        if await selectionIsEmpty(afterSelecting: select != nil) {
            Log.accessibility.debug("\(label, privacy: .public): AX reports an empty selection, nothing to copy")
            return false
        }

        // 1. Read: Accessibility first, pasteboard as fallback
        var selectedText = useAX ? selection.selectedText() : nil
        if selectedText == nil {
            savedContents = pasteboard.snapshot()
            let clearedCount = pasteboard.clear()
            keystrokes.send(.copy)
            let copied = await waitForPasteboardChange(from: clearedCount, timeout: timing.copyTimeout)
            // Whatever is on the pasteboard now was caused by our clear and ⌘C.
            ownChangeCount = pasteboard.changeCount
            if copied, let text = pasteboard.string(), !text.isEmpty {
                selectedText = text
            } else {
                Log.accessibility.debug(
                    "\(label, privacy: .public): no text on pasteboard after ⌘C (changed=\(copied))")
            }
        }

        guard let selectedText else {
            if select != nil { undoSelection(selectionToRestore, keystrokes: keystrokes) }
            if let savedContents { restoreIfUntouched(savedContents, ownChangeCount: ownChangeCount) }
            return false
        }

        Log.accessibility.debug(
            "\(label, privacy: .public): read = '\(selectedText, privacy: .private)' (len=\(selectedText.count))")

        guard let convertedText = converter(selectedText) else {
            Log.accessibility.debug("\(label, privacy: .public): converter returned nil")
            if select != nil { undoSelection(selectionToRestore, keystrokes: keystrokes) }
            if let savedContents { restoreIfUntouched(savedContents, ownChangeCount: ownChangeCount) }
            return false
        }

        // 2. Replace. Overlays: type over the selection, no pasteboard needed.
        if overlayFocused {
            Log.focus.debug("\(label, privacy: .public): replace path = typing")
            keystrokes.send(.typeText(convertedText))
            if let savedContents { restoreIfUntouched(savedContents, ownChangeCount: ownChangeCount) }
            return true
        }

        // Accessibility first. Fall back only if the text is provably unchanged,
        // otherwise the converted text could end up inserted twice.
        let axResult = useAX ? await selection.replaceSelectedText(with: convertedText) : .unchanged
        if axResult != .unchanged {
            Log.accessibility.debug(
                "\(label, privacy: .public): replaced via AX (\(String(describing: axResult), privacy: .public))")
            if let savedContents { restoreIfUntouched(savedContents, ownChangeCount: ownChangeCount) }
            return true
        }

        Log.accessibility.debug("\(label, privacy: .public): pasting = '\(convertedText, privacy: .private)'")

        let contentsToRestore = savedContents ?? pasteboard.snapshot()
        ownChangeCount = pasteboard.writeTemporary(convertedText)
        keystrokes.send(.paste)

        try? await Task.sleep(for: timing.pasteSettle)
        restoreIfUntouched(contentsToRestore, ownChangeCount: ownChangeCount)

        return true
    }

    /// Puts the selection back as it was before we selected the text to convert.
    private func undoSelection(_ range: NSRange?, keystrokes: KeystrokeSender) {
        if let range, selection.setSelectedRange(range) { return }
        keystrokes.send(.rightArrow)
    }

    // MARK: - Waiting

    /// True only if AX positively reports an empty selection; unknown counts as not empty.
    /// After a selection keystroke, waits for the app to apply it (Electron updates AX lazily).
    private func selectionIsEmpty(afterSelecting: Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timing.selectionTimeout)
        while true {
            guard let length = selection.selectedLength() else { return false }
            if length > 0 { return false }
            guard afterSelecting, clock.now < deadline else { return true }
            do {
                try await Task.sleep(for: timing.pollInterval)
            } catch {
                return false
            }
        }
    }

    /// Polls changeCount until it differs from `count`. Returns false on timeout or cancellation.
    func waitForPasteboardChange(from count: Int, timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while pasteboard.changeCount == count {
            guard clock.now < deadline else { return false }
            do {
                try await Task.sleep(for: timing.pollInterval)
            } catch {
                return false
            }
        }
        return true
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
