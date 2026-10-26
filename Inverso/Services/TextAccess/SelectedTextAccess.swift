import Foundation

/// The selection of the focused text element, read and replaced without the pasteboard.
/// Lets tests substitute a fake.
@MainActor
protocol SelectedTextAccess {
    /// Selected text of the focused element, or nil if empty or not available via AX.
    func selectedText() -> String?
    /// Length of the focused element's selection (UTF-16), or nil if AX doesn't report it.
    func selectedLength() -> Int?
    func replaceSelectedText(with text: String) async -> AXReplaceResult
    /// Value and selected range of the focused element, or nil if AX doesn't report them.
    func textState() -> OverlayTextSelection.State?
    /// Selects `range` via kAXSelectedTextRangeAttribute. False if the attribute is not
    /// settable or the element reports another range afterwards.
    func setSelectedRange(_ range: NSRange) -> Bool
    /// Access to the focused element of the overlay process `pid` (Spotlight, Open/Save panels)
    /// instead of the system-wide focus; nil keeps the system-wide focus.
    func focused(onOverlay pid: pid_t?) -> SelectedTextAccess
}

extension SelectedTextAccess {
    func focused(onOverlay pid: pid_t?) -> SelectedTextAccess { self }
}
