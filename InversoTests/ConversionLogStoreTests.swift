import XCTest

@testable import Inverso

@MainActor
final class ConversionLogStoreTests: XCTestCase {

    private var root: URL!
    private var store: ConversionLogStore!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = ConversionLogStore(databaseURL: root.appendingPathComponent("log.sqlite"))
    }

    override func tearDown() async throws {
        store.close()
        await store.flush()
        try? FileManager.default.removeItem(at: root)
    }

    private func add(_ input: String, output: String = "out") {
        store.log(
            inputText: input,
            outputText: output,
            sourceLayout: "us",
            targetLayout: "russian",
            conversionMode: "direct"
        )
    }

    func testStoresEmojiCyrillicAndLongTextByteForByte() async {
        let emoji = "🙂👩‍👩‍👧‍👦 e\u{301}"
        let cyrillic = "Привет, мир! ёЁ"
        let long = String(repeating: "длинный текст 🚀 ", count: 600)
        XCTAssertGreaterThan(long.utf8.count, 4096)

        add(emoji, output: cyrillic)
        add(long, output: long)
        await store.flush()

        // Reload from disk so the values come from SQLite, not from memory
        store.close()
        store.loadIfNeeded()
        await store.flush()

        let byInput = Dictionary(uniqueKeysWithValues: store.logs.map { ($0.inputText.utf8.map { $0 }, $0) })
        XCTAssertEqual(store.logs.count, 2)
        XCTAssertEqual(byInput[Array(emoji.utf8)]?.outputText.utf8.map { $0 }, Array(cyrillic.utf8))
        XCTAssertEqual(byInput[Array(long.utf8)]?.outputText.utf8.map { $0 }, Array(long.utf8))
    }

    func testClearAllRightAfterLogDoesNotResurrectEntry() async {
        store.loadIfNeeded()
        await store.flush()

        add("ghbdtn")
        store.clearAll()
        await store.flush()

        XCTAssertTrue(store.logs.isEmpty)
    }

    func testDeleteRightAfterLogDoesNotResurrectEntry() async throws {
        store.loadIfNeeded()
        add("first")
        await store.flush()
        let firstID = try XCTUnwrap(store.logs.first?.id)

        add("second")
        store.delete(id: firstID)
        await store.flush()

        XCTAssertEqual(store.logs.map(\.inputText), ["second"])
    }
}
