import AppKit

/// Saved pasteboard contents: every item with every data representation, in original order.
struct PasteboardSnapshot: Equatable {
    struct Representation: Equatable {
        let type: NSPasteboard.PasteboardType
        let data: Data
    }

    struct Item: Equatable {
        var representations: [Representation]
    }

    var items: [Item]
}
