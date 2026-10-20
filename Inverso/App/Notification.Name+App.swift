import Foundation

extension Notification.Name {
    /// Asks MenuBarLabel to open the Settings scene (for code outside SwiftUI views).
    static let openSettingsRequest = Notification.Name("openSettingsRequest")
    /// The hotkey settings changed; the hotkey must be registered again.
    static let hotkeySettingsChanged = Notification.Name("hotkeySettingsChanged")
}
