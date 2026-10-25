import AppKit

/// Terminals: selecting with ⌘⇧← / ⌥⇧←, ⌘C and ⌘V there would send keys to the shell or the
/// running program, so the hotkey does nothing in them except show a hint.
enum TerminalApps {
    static let bundleIDs: Set<String> = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.mitchellh.ghostty",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "com.github.wez.wezterm",
    ]

    static func matches(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleIDs.contains(bundleID)
    }

    /// True if a terminal has the keyboard focus. Spotlight or an Open/Save panel above
    /// a terminal has the focus itself, so conversion works there.
    static func hasFocus(frontmostBundleID: String?, overlayFocused: Bool) -> Bool {
        AppRuleRegistry.focusMode(
            frontmostBundleID: frontmostBundleID,
            overlayPID: overlayFocused ? 1 : nil
        ) == .terminal
    }

    @MainActor
    static func hasFocus() -> Bool {
        AppRuleRegistry.isTerminalFocused()
    }
}
