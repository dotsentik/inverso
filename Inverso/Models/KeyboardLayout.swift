import Foundation

/// A keyboard layout input source of the system.
struct KeyboardLayout: Identifiable, Hashable, Codable {
    /// Input source ID, e.g. "com.apple.keylayout.US".
    let id: String
    /// Name shown by the system, e.g. "U.S." or "Russian".
    let localizedName: String
    /// First language of the input source, e.g. "en", "ru"; "unknown" if the system has none.
    let languageCode: String
}
