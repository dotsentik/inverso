import Foundation

/// What the user sees after a successful conversion. Sound is a separate setting.
/// Raw values are stored in UserDefaults.
enum ConversionFeedback: Int, CaseIterable, Codable {
    /// Small overlay at the top of the screen.
    case hud = 0
    /// System notification (Notification Center).
    case notification = 1
    case none = 2
}
