import AppKit

extension NSPasteboard.PasteboardType {
    /// nspasteboard.org marker: clipboard managers should not record these contents.
    static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    /// nspasteboard.org marker: clipboard managers should not display these contents.
    static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
}
