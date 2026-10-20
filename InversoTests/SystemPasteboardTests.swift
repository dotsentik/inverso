import AppKit
import XCTest

@testable import Inverso

/// Runs against a real, uniquely named NSPasteboard — the user's clipboard is not touched.
@MainActor
final class SystemPasteboardTests: XCTestCase {

    private var nsPasteboard: NSPasteboard!
    private var pasteboard: SystemPasteboard!

    private let customType = NSPasteboard.PasteboardType("com.dotsentik.inversoTests.custom")

    override func setUp() async throws {
        try await super.setUp()
        nsPasteboard = NSPasteboard(name: NSPasteboard.Name("com.dotsentik.inversoTests.\(UUID().uuidString)"))
        pasteboard = SystemPasteboard(nsPasteboard)
    }

    override func tearDown() async throws {
        nsPasteboard.releaseGlobally()
        nsPasteboard = nil
        pasteboard = nil
        try await super.tearDown()
    }

    func testWriteTemporary_IsMarkedTransientAndConcealed() {
        let before = nsPasteboard.changeCount

        let count = pasteboard.writeTemporary("привет")

        XCTAssertGreaterThan(count, before)
        XCTAssertEqual(count, nsPasteboard.changeCount)
        XCTAssertEqual(nsPasteboard.string(forType: .string), "привет")
        let types = nsPasteboard.pasteboardItems?.first?.types ?? []
        XCTAssertTrue(types.contains(.transient))
        XCTAssertTrue(types.contains(.concealed))
    }

    func testSnapshotAndRestore_KeepAllItemsAndTypes() throws {
        let rtf = Data(#"{\rtf1 hello}"#.utf8)
        let image = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF])
        let first = NSPasteboardItem()
        first.setString("hello", forType: .string)
        first.setData(rtf, forType: .rtf)
        first.setData(image, forType: customType)
        let second = NSPasteboardItem()
        second.setString("https://example.com", forType: .URL)
        nsPasteboard.clearContents()
        nsPasteboard.writeObjects([first, second])

        let snapshot = pasteboard.snapshot()
        pasteboard.writeTemporary("temporary")
        pasteboard.restore(snapshot)

        let items = try XCTUnwrap(nsPasteboard.pasteboardItems)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items[0].string(forType: .string), "hello")
        XCTAssertEqual(items[0].data(forType: .rtf), rtf)
        XCTAssertEqual(items[0].data(forType: customType), image)
        XCTAssertEqual(items[1].string(forType: .URL), "https://example.com")
        XCTAssertFalse(items[0].types.contains(.concealed), "our concealed marker is gone")
    }

    func testRestoredContents_AreMarkedTransient() {
        nsPasteboard.clearContents()
        nsPasteboard.setString("user text", forType: .string)

        let snapshot = pasteboard.snapshot()
        pasteboard.writeTemporary("temporary")
        pasteboard.restore(snapshot)

        let types = nsPasteboard.pasteboardItems?.first?.types ?? []
        XCTAssertTrue(types.contains(.transient), "clipboard managers should not record it a second time")
        XCTAssertEqual(nsPasteboard.string(forType: .string), "user text")
    }

    func testRestoreEmptySnapshot_LeavesPasteboardEmpty() {
        nsPasteboard.clearContents()
        let snapshot = pasteboard.snapshot()
        XCTAssertTrue(snapshot.items.isEmpty)

        pasteboard.writeTemporary("temporary")
        pasteboard.restore(snapshot)

        XCTAssertNil(nsPasteboard.string(forType: .string))
        XCTAssertEqual(nsPasteboard.pasteboardItems?.count ?? 0, 0)
    }

    func testClear_ReturnsNewChangeCount() {
        let before = nsPasteboard.changeCount
        let count = pasteboard.clear()
        XCTAssertGreaterThan(count, before)
        XCTAssertEqual(count, nsPasteboard.changeCount)
    }
}
