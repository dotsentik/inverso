import Foundation

/// The user's choices that conversion depends on. Read on the main actor, where settings live.
@MainActor
protocol ConversionPreferences: AnyObject {
    /// Enabled layout IDs in user priority order (highest first).
    var enabledLayoutIDs: [String] { get }
    /// Explicit "source → target" layout choices.
    var targetOverrides: [String: String] { get }
}
