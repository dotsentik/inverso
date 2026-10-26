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

        /// PID of the overlay that owns keyboard focus, if any.
        var overlayPID: pid_t? {
            if case .overlay(let pid) = self { return pid }
            return nil
        }
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
}
