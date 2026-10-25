import AppKit

/// Single entry point for application-specific focus and text access rules, unifying
/// `TerminalApps`, `ClipboardOnlyApps`, and `KeyboardFocusOwner`.
enum AppRuleRegistry {

    /// Interaction mode for the currently focused application or system overlay.
    enum FocusMode: Equatable {
        /// A terminal emulator has keyboard focus: skip conversion and show a hint.
        case terminal
        /// A non-activating overlay (Spotlight or Open/Save panel) owns keyboard focus.
        case overlay(pid_t)
        /// An app (such as Electron/Chromium) where AX text writes are unreliable: use ⌘C/⌘V only.
        case clipboardOnly
        /// A regular app: try AX selection access first, then fall back to ⌘C/⌘V.
        case standard
    }

    /// Resolves the focus mode from the active overlay PID and frontmost app metadata.
    /// An active overlay always takes precedence over the frontmost application behind it.
    static func focusMode(
        frontmostBundleID: String?,
        frontmostBundleURL: URL? = nil,
        overlayPID: pid_t? = nil
    ) -> FocusMode {
        if let overlayPID {
            return .overlay(overlayPID)
        }
        if TerminalApps.matches(bundleID: frontmostBundleID) {
            return .terminal
        }
        if ClipboardOnlyApps.matches(bundleID: frontmostBundleID, bundleURL: frontmostBundleURL) {
            return .clipboardOnly
        }
        return .standard
    }

    /// PID of the overlay process that currently owns keyboard focus, if any.
    static func overlayPID() -> pid_t? {
        KeyboardFocusOwner.overlayPID()
    }

    /// Resolves the live focus mode from the window server and frontmost application.
    @MainActor
    static func currentFocusMode() -> FocusMode {
        let app = NSWorkspace.shared.frontmostApplication
        return focusMode(
            frontmostBundleID: app?.bundleIdentifier,
            frontmostBundleURL: app?.bundleURL,
            overlayPID: KeyboardFocusOwner.overlayPID()
        )
    }

    /// True when a terminal is frontmost and no system overlay is open above it.
    @MainActor
    static func isTerminalFocused() -> Bool {
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        guard TerminalApps.matches(bundleID: frontmost) else { return false }
        return focusMode(
            frontmostBundleID: frontmost,
            overlayPID: KeyboardFocusOwner.overlayPID()
        ) == .terminal
    }

    /// True when the frontmost application requires clipboard-only text access.
    @MainActor
    static func isClipboardOnlyFrontmost() -> Bool {
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        return focusMode(
            frontmostBundleID: app.bundleIdentifier,
            frontmostBundleURL: app.bundleURL
        ) == .clipboardOnly
    }
}
