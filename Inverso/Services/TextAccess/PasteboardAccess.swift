import Foundation

/// The slice of NSPasteboard the conversion chain needs. Lets tests substitute a fake.
@MainActor
protocol PasteboardAccess: AnyObject {
    /// Increases every time the pasteboard contents change (ours or another app's write).
    var changeCount: Int { get }
    func string() -> String?
    /// Removes the contents. Returns the new change count.
    @discardableResult func clear() -> Int
    /// Replaces the contents with our temporary text, marked transient and concealed.
    /// Returns the new change count.
    @discardableResult func writeTemporary(_ text: String) -> Int
    func snapshot() -> PasteboardSnapshot
    /// Puts saved contents back, marked transient so clipboard managers don't record them twice.
    func restore(_ snapshot: PasteboardSnapshot)
}
