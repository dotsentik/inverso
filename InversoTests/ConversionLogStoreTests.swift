import SQLite3
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

    private func add(_ input: String, output: String = "out", trimTo: Int = 0) {
        store.log(
            inputText: input,
            outputText: output,
            sourceLayout: "us",
            targetLayout: "russian",
            conversionMode: "direct",
            trimTo: trimTo
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

    func testDatabaseFilesAreOwnerOnly() async throws {
        add("secret")
        await store.flush()
        let path = root.appendingPathComponent("log.sqlite").path
        // Files that already exist with wide permissions are tightened too
        for suffix in ["-wal", "-shm"] where !FileManager.default.fileExists(atPath: path + suffix) {
            FileManager.default.createFile(atPath: path + suffix, contents: nil)
        }
        for suffix in ["", "-wal", "-shm"] {
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path + suffix)
        }

        ConversionLogStore.restrictPermissions(ofDatabaseAt: path)

        for suffix in ["", "-wal", "-shm"] {
            let mode = try FileManager.default.attributesOfItem(atPath: path + suffix)[.posixPermissions] as? Int
            XCTAssertEqual(mode, 0o600, "log.sqlite\(suffix)")
        }
    }

    func testClearAllRightAfterLogDoesNotResurrectEntry() async {
        store.loadIfNeeded()
        await store.flush()

        add("ghbdtn")
        store.clearAll()
        await store.flush()

        XCTAssertTrue(store.logs.isEmpty)
    }

    /// Bytes of the database and its journal files: deleted text must not survive in free pages.
    private func databaseBytes() -> Data {
        let path = root.appendingPathComponent("log.sqlite").path
        return ["", "-journal", "-wal", "-shm"].reduce(into: Data()) { data, suffix in
            data.append(FileManager.default.contents(atPath: path + suffix) ?? Data())
        }
    }

    func testClearAllLeavesNoTextInTheDatabaseFile() async {
        let secret = "cleared-secret-" + UUID().uuidString
        store.loadIfNeeded()
        add(secret, output: secret)
        await store.flush()
        XCTAssertNotNil(databaseBytes().range(of: Data(secret.utf8)))

        store.clearAll()
        store.close()
        await store.flush()

        XCTAssertNil(databaseBytes().range(of: Data(secret.utf8)))
    }

    func testDeleteLeavesNoTextInTheDatabaseFile() async throws {
        let secret = "deleted-secret-" + UUID().uuidString
        store.loadIfNeeded()
        add(secret, output: secret)
        add("kept")
        await store.flush()
        let id = try XCTUnwrap(store.logs.first(where: { $0.inputText == secret })?.id)

        store.delete(id: id)
        store.close()
        await store.flush()

        XCTAssertNil(databaseBytes().range(of: Data(secret.utf8)))
    }

    func testDoesNotOpenTheDatabaseThroughASymlink() async throws {
        let target = root.appendingPathComponent("other-file")
        FileManager.default.createFile(atPath: target.path, contents: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        let link = root.appendingPathComponent("linked.sqlite")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let linkedStore = ConversionLogStore(databaseURL: link)

        linkedStore.loadIfNeeded()
        linkedStore.log(
            inputText: "x", outputText: "y", sourceLayout: "us", targetLayout: "russian", conversionMode: "direct")
        await linkedStore.flush()

        XCTAssertFalse(linkedStore.isDatabaseOpen)
        XCTAssertEqual(try Data(contentsOf: target), Data())
        let mode = try FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? Int
        XCTAssertEqual(mode, 0o644)
        linkedStore.close()
        await linkedStore.flush()
    }

    func testLoadsRowsWithNullTextFromAnOlderDatabase() async throws {
        let url = root.appendingPathComponent("old.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        let sql = """
            CREATE TABLE conversion_log (id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp REAL,
                input_text TEXT, output_text TEXT, source_layout TEXT, target_layout TEXT,
                conversion_mode TEXT, is_correct INTEGER);
            INSERT INTO conversion_log (timestamp) VALUES (1);
            """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        sqlite3_close(db)
        let oldStore = ConversionLogStore(databaseURL: url)

        oldStore.loadIfNeeded()
        await oldStore.flush()

        XCTAssertEqual(oldStore.logs.map(\.inputText), [""])
        oldStore.close()
        await oldStore.flush()
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

    func testLogTrimsToLimitInOneOperation() async {
        store.loadIfNeeded()
        for index in 0..<5 {
            add("entry \(index)", trimTo: 3)
        }
        await store.flush()

        XCTAssertEqual(store.logs.count, 3)

        store.close()
        store.loadIfNeeded()
        await store.flush()
        XCTAssertEqual(store.logs.count, 3)
    }

    /// The limit comes from defaults unchecked (`defaults write … logMaxEntries`).
    func testLimitAboveInt32KeepsEverythingWithoutCrashing() async {
        store.loadIfNeeded()
        add("first", trimTo: Int(Int32.max) + 1)
        add("second", trimTo: Int(Int32.max) + 1)
        await store.flush()

        XCTAssertEqual(store.logs.count, 2)
    }
}
