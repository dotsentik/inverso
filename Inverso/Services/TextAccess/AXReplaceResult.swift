import Foundation

/// Outcome of replacing the selection through kAXSelectedTextAttribute.
enum AXReplaceResult: Equatable {
    /// The value now equals the old value with the selection replaced.
    case replaced
    /// Nothing changed (or the write was not attempted): safe to fall back to the pasteboard.
    case unchanged
    /// The value changed, but not as expected. Falling back could insert the text twice.
    case unknown
}
