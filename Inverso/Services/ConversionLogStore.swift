import Foundation
import SQLite3

/// Stores the conversion log in a local SQLite database through the SQLite3 C API.
@MainActor
final class ConversionLogStore: ObservableObject {

    static let shared = ConversionLogStore()

    @Published private(set) var logs: [ConversionLog] = []

    // Touched from nonisolated deinit only; all other access is on the main actor.
    nonisolated(unsafe) private var db: OpaquePointer?

    private init() {
        openDatabase()
        createTableIfNeeded()
        reload()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    // MARK: - Database

    nonisolated static let databaseFileName = "conversion_log.sqlite"

    private static var databasePath: String {
        let appSupport = URL.applicationSupportDirectory
        let dir = appSupport.appendingPathComponent("Inverso", isDirectory: true)
        // Data directory of the app's former name
        let legacyDir = appSupport.appendingPathComponent("LangSwitcher", isDirectory: true)
        migrateLegacyLog(from: legacyDir, to: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent(databaseFileName).path
    }

    /// Copies the log from `legacyDir` on the first launch: only when `legacyDir` exists and
    /// `dir` does not. `legacyDir` is left untouched. Returns true if the log was copied.
    @discardableResult
    nonisolated static func migrateLegacyLog(
        from legacyDir: URL, to dir: URL, fileManager: FileManager = .default
    ) -> Bool {
        guard fileManager.fileExists(atPath: legacyDir.path), !fileManager.fileExists(atPath: dir.path) else {
            return false
        }
        let legacyLog = legacyDir.appendingPathComponent(databaseFileName)
        guard fileManager.fileExists(atPath: legacyLog.path) else { return false }
        do {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            try fileManager.copyItem(at: legacyLog, to: dir.appendingPathComponent(databaseFileName))
            return true
        } catch {
            Log.logStore.error(
                "Failed to copy the old log: \((error as NSError).domain, privacy: .public) \((error as NSError).code, privacy: .public)"
            )
            return false
        }
    }

    private func openDatabase() {
        let path = Self.databasePath
        Log.logStore.debug("Opening database at \(path, privacy: .private)")

        if sqlite3_open(path, &db) != SQLITE_OK {
            let err = db.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            Log.logStore.error("Failed to open database: \(err, privacy: .public)")
            db = nil
        }
    }

    private func createTableIfNeeded() {
        guard let db else { return }

        let sql = """
            CREATE TABLE IF NOT EXISTS conversion_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp REAL NOT NULL,
                input_text TEXT NOT NULL,
                output_text TEXT NOT NULL,
                source_layout TEXT NOT NULL,
                target_layout TEXT NOT NULL,
                conversion_mode TEXT NOT NULL,
                is_correct INTEGER
            );
            """

        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) != SQLITE_OK {
            let err = errMsg.map { String(cString: $0) } ?? "unknown"
            Log.logStore.error("Failed to create table: \(err, privacy: .public)")
            sqlite3_free(errMsg)
        } else {
            Log.logStore.debug("Table ready")
        }
    }

    // MARK: - Entries

    func log(
        inputText: String,
        outputText: String,
        sourceLayout: String,
        targetLayout: String,
        conversionMode: String
    ) {
        guard let db else { return }

        let sql = """
            INSERT INTO conversion_log (timestamp, input_text, output_text, source_layout, target_layout, conversion_mode, is_correct)
            VALUES (?, ?, ?, ?, ?, ?, NULL);
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.logStore.error("Failed to prepare INSERT")
            return
        }
        defer { sqlite3_finalize(stmt) }

        let timestamp = Date().timeIntervalSince1970
        sqlite3_bind_double(stmt, 1, timestamp)
        sqlite3_bind_text(stmt, 2, (inputText as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 3, (outputText as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 4, (sourceLayout as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 5, (targetLayout as NSString).utf8String, -1, nil)
        sqlite3_bind_text(stmt, 6, (conversionMode as NSString).utf8String, -1, nil)

        if sqlite3_step(stmt) == SQLITE_DONE {
            Log.logStore.debug(
                "Logged conversion '\(inputText, privacy: .private)' -> '\(outputText, privacy: .private)'")
            reload()
        } else {
            Log.logStore.error("INSERT failed")
        }
    }

    /// Reads all entries into `logs`, newest first.
    private func reload() {
        guard let db else { return }

        let sql =
            "SELECT id, timestamp, input_text, output_text, source_layout, target_layout, conversion_mode, is_correct FROM conversion_log ORDER BY timestamp DESC;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.logStore.error("Failed to prepare SELECT")
            return
        }
        defer { sqlite3_finalize(stmt) }

        var results: [ConversionLog] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let inputText = String(cString: sqlite3_column_text(stmt, 2))
            let outputText = String(cString: sqlite3_column_text(stmt, 3))
            let sourceLayout = String(cString: sqlite3_column_text(stmt, 4))
            let targetLayout = String(cString: sqlite3_column_text(stmt, 5))
            let conversionMode = String(cString: sqlite3_column_text(stmt, 6))

            let isCorrect: Bool?
            if sqlite3_column_type(stmt, 7) == SQLITE_NULL {
                isCorrect = nil
            } else {
                isCorrect = sqlite3_column_int(stmt, 7) != 0
            }

            results.append(
                ConversionLog(
                    id: id,
                    timestamp: timestamp,
                    inputText: inputText,
                    outputText: outputText,
                    sourceLayout: sourceLayout,
                    targetLayout: targetLayout,
                    conversionMode: conversionMode,
                    isCorrect: isCorrect
                ))
        }

        logs = results
    }

    /// Sets the is_correct rating for a log entry. Pass nil to clear the rating.
    func updateRating(id: Int64, isCorrect: Bool?) {
        guard let db else { return }

        let sql = "UPDATE conversion_log SET is_correct = ? WHERE id = ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.logStore.error("Failed to prepare UPDATE")
            return
        }
        defer { sqlite3_finalize(stmt) }

        if let isCorrect {
            sqlite3_bind_int(stmt, 1, isCorrect ? 1 : 0)
        } else {
            sqlite3_bind_null(stmt, 1)
        }
        sqlite3_bind_int64(stmt, 2, id)

        if sqlite3_step(stmt) == SQLITE_DONE, let index = logs.firstIndex(where: { $0.id == id }) {
            logs[index].isCorrect = isCorrect
        }
    }

    func delete(id: Int64) {
        guard let db else { return }

        let sql = "DELETE FROM conversion_log WHERE id = ?;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, id)

        if sqlite3_step(stmt) == SQLITE_DONE {
            logs.removeAll { $0.id == id }
        }
    }

    /// Deletes the oldest entries so that at most `max` remain. 0 = unlimited, nothing is deleted.
    func trim(toMaxEntries max: Int) {
        guard max > 0, let db else { return }

        let sql = """
            DELETE FROM conversion_log WHERE id NOT IN (
                SELECT id FROM conversion_log ORDER BY timestamp DESC LIMIT ?
            );
            """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.logStore.error("Failed to prepare TRIM")
            return
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int(stmt, 1, Int32(max))

        if sqlite3_step(stmt) == SQLITE_DONE {
            let deleted = sqlite3_changes(db)
            if deleted > 0 {
                Log.logStore.info("Trimmed \(deleted) old entries (max: \(max))")
                reload()
            }
        } else {
            Log.logStore.error("TRIM failed")
        }
    }

    func clearAll() {
        guard let db else { return }

        let sql = "DELETE FROM conversion_log;"
        var errMsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK {
            logs.removeAll()
            Log.logStore.info("Cleared all logs")
        }
        sqlite3_free(errMsg)
    }

    // MARK: - Export

    /// All entries as a pretty-printed JSON array.
    func exportJSON() -> String {
        struct ExportEntry: Codable {
            let id: Int64
            let timestamp: String
            let inputText: String
            let outputText: String
            let sourceLayout: String
            let targetLayout: String
            let conversionMode: String
            let isCorrect: Bool?
        }

        let formatter = ISO8601DateFormatter()
        let entries = logs.map { log in
            ExportEntry(
                id: log.id,
                timestamp: formatter.string(from: log.timestamp),
                inputText: log.inputText,
                outputText: log.outputText,
                sourceLayout: log.sourceLayout,
                targetLayout: log.targetLayout,
                conversionMode: log.conversionMode,
                isCorrect: log.isCorrect
            )
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries),
            let json = String(data: data, encoding: .utf8)
        {
            return json
        }
        return "[]"
    }
}
