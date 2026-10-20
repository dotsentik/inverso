import Foundation

/// Sends keystrokes to the frontmost app. Lets tests substitute a fake app.
@MainActor
protocol KeystrokeSender {
    func send(_ keystroke: Keystroke)
    /// A sender whose events reach the window with the keyboard focus even if its process
    /// is not the frontmost app (Spotlight, Open/Save panels).
    func routedToKeyWindow() -> KeystrokeSender
}

extension KeystrokeSender {
    func routedToKeyWindow() -> KeystrokeSender { self }
}
