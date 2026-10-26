import Foundation

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
}
