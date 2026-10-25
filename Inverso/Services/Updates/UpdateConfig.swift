import Foundation

/// Where and how often the app looks for updates. Info.plist carries the same values for
/// Sparkle (SUFeedURL, SUScheduledCheckInterval); UpdateConfigTests keep the two in sync.
enum UpdateConfig {
    /// Appcast with the published releases. The only network request the app makes.
    static let feedURL =
        URL(string: "https://raw.githubusercontent.com/dotsentik/inverso/main/appcast.xml") ?? URL(fileURLWithPath: "/")

    /// Time between automatic update checks: once a day.
    static let checkInterval: TimeInterval = 24 * 60 * 60

    /// Info.plist keys read by Sparkle.
    enum InfoKey {
        static let feedURL = "SUFeedURL"
        static let publicEDKey = "SUPublicEDKey"
        static let enableAutomaticChecks = "SUEnableAutomaticChecks"
        static let scheduledCheckInterval = "SUScheduledCheckInterval"
    }
}
