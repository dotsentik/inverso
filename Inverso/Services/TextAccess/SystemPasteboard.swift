import AppKit

/// PasteboardAccess over a real NSPasteboard.
@MainActor
final class SystemPasteboard: PasteboardAccess {
    private let pasteboard: NSPasteboard

    init(_ pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func string() -> String? {
        pasteboard.string(forType: .string)
    }

    @discardableResult func clear() -> Int {
        pasteboard.clearContents()
    }

    @discardableResult func writeTemporary(_ text: String) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: .transient)
        item.setData(Data(), forType: .concealed)
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    func snapshot() -> PasteboardSnapshot {
        let items =
            pasteboard.pasteboardItems?.map { item in
                PasteboardSnapshot.Item(
                    representations: item.types.compactMap { type in
                        item.data(forType: type).map { PasteboardSnapshot.Representation(type: type, data: $0) }
                    })
            } ?? []
        return PasteboardSnapshot(items: items)
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        pasteboard.clearContents()
        let items = snapshot.items.map { saved in
            let item = NSPasteboardItem()
            for representation in saved.representations {
                item.setData(representation.data, forType: representation.type)
            }
            if !saved.representations.contains(where: { $0.type == .transient }) {
                item.setData(Data(), forType: .transient)
            }
            return item
        }
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }
}
