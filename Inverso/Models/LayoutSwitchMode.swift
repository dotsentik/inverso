import Foundation

/// When the system keyboard layout switches after a conversion. Raw values are stored in UserDefaults.
enum LayoutSwitchMode: Int, CaseIterable, Codable {
    case always = 0
    /// If the last word was in the wrong layout and got converted.
    case ifLastWordConverted = 1
    /// If any word of the converted text needed conversion.
    case ifAnyWordConverted = 2
}
