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
}
