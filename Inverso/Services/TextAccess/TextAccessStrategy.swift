import Foundation

/// Strategy governing how `AccessibilityService` selects, reads, and replaces text for a focus target.
struct TextAccessStrategy: Equatable {

    /// How the strategy selects text before the cursor when no selection exists yet.
    enum SelectionMethod: Equatable {
        /// Sends selection keystrokes (⇧⌥← or ⌘⇧←) directly to the target app.
        case keystrokes
        /// Selects the range via `kAXSelectedTextRangeAttribute` first, falling back to keystrokes.
        case axRangeWithKeystrokeFallback
    }

    /// How the strategy reads the currently selected text.
    enum ReadMethod: Equatable {
        /// Reads `kAXSelectedTextAttribute` first, falling back to ⌘C via the pasteboard.
        case axWithPasteboardFallback
        /// Skips AX text attributes and copies strictly via ⌘C on the pasteboard.
        case pasteboardOnly
    }

    /// How the strategy writes the converted text back to the target field.
    enum ReplaceMethod: Equatable {
        /// Writes `kAXSelectedTextAttribute` (with verification) first, falling back to ⌘V.
        case axWithPasteboardFallback
        /// Skips AX writes and pastes strictly via ⌘V.
        case pasteboardOnly
        /// Types the replacement characters via `CGEvent` keystrokes without touching the pasteboard.
        case typing
    }

    let selectionMethod: SelectionMethod
    let readMethod: ReadMethod
    let replaceMethod: ReplaceMethod
    let routesKeystrokesToKeyWindow: Bool

    /// Standard macOS apps: AX read/write first, ⌘C/⌘V pasteboard fallback.
    static let standard = TextAccessStrategy(
        selectionMethod: .keystrokes,
        readMethod: .axWithPasteboardFallback,
        replaceMethod: .axWithPasteboardFallback,
        routesKeystrokesToKeyWindow: false
    )

    /// Electron/Chromium apps where AX writes report success without changing text: ⌘C/⌘V only.
    static let clipboardOnly = TextAccessStrategy(
        selectionMethod: .keystrokes,
        readMethod: .pasteboardOnly,
        replaceMethod: .pasteboardOnly,
        routesKeystrokesToKeyWindow: false
    )

    /// Non-activating overlays (Spotlight, Open/Save panels): AX range selection, AX-first read, typed replacement.
    static let overlay = TextAccessStrategy(
        selectionMethod: .axRangeWithKeystrokeFallback,
        readMethod: .axWithPasteboardFallback,
        replaceMethod: .typing,
        routesKeystrokesToKeyWindow: true
    )

    /// Resolves the text access strategy for a focus mode from `AppRuleRegistry`.
    static func resolve(for focusMode: AppRuleRegistry.FocusMode) -> TextAccessStrategy? {
        switch focusMode {
        case .terminal:
            return nil
        case .overlay:
            return .overlay
        case .clipboardOnly:
            return .clipboardOnly
        case .standard:
            return .standard
        }
    }

    /// Resolves the text access strategy from focus flags.
    static func resolve(overlayFocused: Bool, clipboardOnly: Bool) -> TextAccessStrategy {
        if overlayFocused {
            return .overlay
        }
        if clipboardOnly {
            return .clipboardOnly
        }
        return .standard
    }
}
