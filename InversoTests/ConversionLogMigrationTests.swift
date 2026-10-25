import XCTest

@testable import Inverso

final class ConversionLogMigrationTests: XCTestCase {

    private var root: URL!
    private var legacyDir: URL { root.appendingPathComponent("LangSwitcher", isDirectory: true) }
    private var dir: URL { root.appendingPathComponent("Inverso", isDirectory: true) }
    private let fileName = ConversionLogStore.databaseFileName

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeLegacyLog(_ content: String = "old log") throws {
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)
        try Data(content.utf8).write(to: legacyDir.appendingPathComponent(fileName))
    }

    func testCopiesTheOldLogAndKeepsTheOldDirectory() throws {
        try writeLegacyLog()

        XCTAssertTrue(ConversionLogStore.migrateLegacyLog(from: legacyDir, to: dir))

        let copied = try String(contentsOf: dir.appendingPathComponent(fileName), encoding: .utf8)
        XCTAssertEqual(copied, "old log")
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyDir.appendingPathComponent(fileName).path))
    }

    func testDoesNothingWhenTheNewDirectoryExists() throws {
        try writeLegacyLog()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        XCTAssertFalse(ConversionLogStore.migrateLegacyLog(from: legacyDir, to: dir))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(fileName).path))
    }

    func testDoesNothingWithoutTheOldDirectory() {
        XCTAssertFalse(ConversionLogStore.migrateLegacyLog(from: legacyDir, to: dir))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testDoesNothingWhenTheOldDirectoryHasNoLog() throws {
        try FileManager.default.createDirectory(at: legacyDir, withIntermediateDirectories: true)

        XCTAssertFalse(ConversionLogStore.migrateLegacyLog(from: legacyDir, to: dir))
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testRunsOnlyOnce() throws {
        try writeLegacyLog("first")
        XCTAssertTrue(ConversionLogStore.migrateLegacyLog(from: legacyDir, to: dir))
        try writeLegacyLog("second")

        XCTAssertFalse(ConversionLogStore.migrateLegacyLog(from: legacyDir, to: dir))
        let copied = try String(contentsOf: dir.appendingPathComponent(fileName), encoding: .utf8)
        XCTAssertEqual(copied, "first")
    }

    @MainActor
    func testDatabaseIsOpenedLazilyAndClosedWhenLoggingDisabled() async throws {
        let dbURL = root.appendingPathComponent("lazy_test.sqlite")
        let store = ConversionLogStore(databaseURL: dbURL)

        // Not opened on init or when logging is disabled
        XCTAssertFalse(store.isDatabaseOpen)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbURL.path))

        store.setLoggingEnabled(false)
        await store.flush()
        XCTAssertFalse(store.isDatabaseOpen)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbURL.path))

        // Opened lazily when logging is enabled
        store.setLoggingEnabled(true)
        await store.flush()
        XCTAssertTrue(store.isDatabaseOpen)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path))
        XCTAssertTrue(store.logs.isEmpty)

        // Background insert, rating update, trim, export, delete, clear
        store.log(
            inputText: "ghbdtn",
            outputText: "привет",
            sourceLayout: "com.apple.keylayout.US",
            targetLayout: "com.apple.keylayout.RussianWin",
            conversionMode: "direct"
        )
        store.log(
            inputText: "rfr ltkf",
            outputText: "как дела",
            sourceLayout: "com.apple.keylayout.US",
            targetLayout: "com.apple.keylayout.RussianWin",
            conversionMode: "greedy"
        )
        await store.flush()
        XCTAssertEqual(store.logs.count, 2)

        let firstID = try XCTUnwrap(store.logs.first?.id)
        store.updateRating(id: firstID, isCorrect: true)
        await store.flush()
        XCTAssertEqual(store.logs.first(where: { $0.id == firstID })?.isCorrect, true)

        let exported = store.exportJSON()
        XCTAssertTrue(exported.contains("привет"))
        XCTAssertTrue(exported.contains("как дела"))

        store.trim(toMaxEntries: 1)
        await store.flush()
        XCTAssertEqual(store.logs.count, 1)

        // Disabling logging closes the SQLite connection and clears in-memory logs
        store.setLoggingEnabled(false)
        await store.flush()
        XCTAssertFalse(store.isDatabaseOpen)
        XCTAssertTrue(store.logs.isEmpty)

        // Re-enabling reloads the persisted entry from disk
        store.setLoggingEnabled(true)
        await store.flush()
        XCTAssertTrue(store.isDatabaseOpen)
        XCTAssertEqual(store.logs.count, 1)

        store.clearAll()
        await store.flush()
        XCTAssertTrue(store.logs.isEmpty)
        store.close()
        await store.flush()
    }
}
