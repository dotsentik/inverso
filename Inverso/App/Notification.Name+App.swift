import Foundation

extension Notification.Name {
    /// Asks MenuBarLabel to open the Settings scene (for code outside SwiftUI views).
    static let openSettingsRequest = Notification.Name("openSettingsRequest")
    /// The hotkey settings changed; the hotkey must be registered again.
    static let hotkeySettingsChanged = Notification.Name("hotkeySettingsChanged")
    /// The shortcut recorder started listening; the hotkey pauses so the recorder sees every key.
    static let hotkeyRecordingStarted = Notification.Name("hotkeyRecordingStarted")
    /// The shortcut recorder stopped (recorded or cancelled); the hotkey resumes.
    static let hotkeyRecordingEnded = Notification.Name("hotkeyRecordingEnded")
}
