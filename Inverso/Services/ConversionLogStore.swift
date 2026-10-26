import Foundation
import SQLite3

/// Stores the conversion log in a local SQLite database through the SQLite3 C API.
/// The database connection is opened lazily on a background serial queue and closed when
/// logging is disabled.
@MainActor
final class ConversionLogStore: ObservableObject {

    @Published private(set) var logs: [ConversionLog] = []

    private let backend: DatabaseBackend

    init(databaseURL: URL? = nil) {
        self.backend = DatabaseBackend(databaseURL: databaseURL)
    }

    /// True when the underlying SQLite connection is currently open.
    var isDatabaseOpen: Bool {
        backend.isOpen
    }

    // MARK: - Database Path & Migration

    nonisolated static let databaseFileName = "conversion_log.sqlite"

    nonisolated fileprivate static func defaultDatabasePath() -> String {
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

    // MARK: - Lifecycle

    /// Lazily opens the database and loads existing entries on the background queue.
    func loadIfNeeded() {
        backend.load { [weak self] entries in
            self?.logs = entries
        }
    }

    /// Closes the SQLite connection on the background queue and clears in-memory entries.
    func close() {
        backend.close { [weak self] in
            self?.logs = []
        }
    }

    /// Opens and loads the database when logging is enabled, or closes it when disabled.
    func setLoggingEnabled(_ enabled: Bool) {
        if enabled {
            loadIfNeeded()
        } else {
            close()
        }
    }

    /// Waits for all queued database operations and their `@MainActor` state updates to finish.
    func flush() async {
        await backend.flush()
    }

    // MARK: - Entries

    func log(
        inputText: String,
        outputText: String,
        sourceLayout: String,
        targetLayout: String,
        conversionMode: String
    ) {
        let timestamp = Date().timeIntervalSince1970
        backend.insert(
            timestamp: timestamp,
            inputText: inputText,
            outputText: outputText,
            sourceLayout: sourceLayout,
            targetLayout: targetLayout,
            conversionMode: conversionMode
        ) { [weak self] entries in
            self?.logs = entries
        }
    }

    /// Sets the is_correct rating for a log entry. Pass nil to clear the rating.
    func updateRating(id: Int64, isCorrect: Bool?) {
        if let index = logs.firstIndex(where: { $0.id == id }) {
            logs[index].isCorrect = isCorrect
        }
        backend.updateRating(id: id, isCorrect: isCorrect)
    }

    func delete(id: Int64) {
        logs.removeAll { $0.id == id }
        backend.delete(id: id)
    }

    /// Deletes the oldest entries so that at most `max` remain. 0 = unlimited, nothing is deleted.
    func trim(toMaxEntries max: Int) {
        guard max > 0 else { return }
        backend.trim(toMaxEntries: max) { [weak self] entries in
            if let entries {
                self?.logs = entries
            }
        }
    }

    func clearAll() {
        logs.removeAll()
        backend.clearAll()
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

// MARK: - Background SQLite Worker

/// Tells SQLite to copy bound text right away, so it does not depend on the lifetime of the Swift string.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class DatabaseBackend: @unchecked Sendable {

    private lazy var queue = DispatchQueue(label: "com.inverso.conversionLogStore", qos: .utility)
    private let customDatabaseURL: URL?
    private var db: OpaquePointer?
    private var hasDispatchedWork = false

    init(databaseURL: URL?) {
        self.customDatabaseURL = databaseURL
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    var isOpen: Bool {
        guard hasDispatchedWork else { return false }
        return queue.sync { db != nil }
    }

    func load(completion: @escaping @MainActor @Sendable ([ConversionLog]) -> Void) {
        hasDispatchedWork = true
        queue.async {
            guard let db = self.openIfNeeded() else { return }
            let entries = self.fetchAll(db: db)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion(entries)
                }
            }
        }
    }

    func close(completion: @escaping @MainActor @Sendable () -> Void) {
        guard hasDispatchedWork else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion()
                }
            }
            return
        }
        queue.async {
            if let currentDB = self.db {
                sqlite3_close(currentDB)
                self.db = nil
                Log.logStore.debug("Closed database")
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    completion()
                }
            }
        }
    }

    func flush() async {
        guard hasDispatchedWork else { return }
        await withCheckedContinuation { continuation in
            queue.async {
                DispatchQueue.main.async {
                    continuation.resume()
                }
            }
        }
    }

    func insert(
        timestamp: Double,
        inputText: String,
        outputText: String,
        sourceLayout: String,
        targetLayout: String,
        conversionMode: String,
        completion: @escaping @MainActor @Sendable ([ConversionLog]) -> Void
    ) {
        hasDispatchedWork = true
        queue.async {
            guard let db = self.openIfNeeded() else { return }

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

            sqlite3_bind_double(stmt, 1, timestamp)
            sqlite3_bind_text(stmt, 2, inputText, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 3, outputText, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 4, sourceLayout, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 5, targetLayout, -1, sqliteTransient)
            sqlite3_bind_text(stmt, 6, conversionMode, -1, sqliteTransient)

            if sqlite3_step(stmt) == SQLITE_DONE {
                Log.logStore.debug(
                    "Logged conversion '\(inputText, privacy: .private)' -> '\(outputText, privacy: .private)'")
                let entries = self.fetchAll(db: db)
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        completion(entries)
                    }
                }
            } else {
                Log.logStore.error("INSERT failed")
            }
        }
    }

    func updateRating(id: Int64, isCorrect: Bool?) {
        hasDispatchedWork = true
        queue.async {
            guard let db = self.openIfNeeded() else { return }

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

            _ = sqlite3_step(stmt)
        }
    }

    func delete(id: Int64) {
        hasDispatchedWork = true
        queue.async {
            guard let db = self.openIfNeeded() else { return }

            let sql = "DELETE FROM conversion_log WHERE id = ?;"

            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_int64(stmt, 1, id)
            _ = sqlite3_step(stmt)
        }
    }

    func trim(
        toMaxEntries max: Int,
        completion: @escaping @MainActor @Sendable ([ConversionLog]?) -> Void
    ) {
        hasDispatchedWork = true
        queue.async {
            guard let db = self.openIfNeeded() else { return }

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
                    let entries = self.fetchAll(db: db)
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            completion(entries)
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            completion(nil)
                        }
                    }
                }
            } else {
                Log.logStore.error("TRIM failed")
            }
        }
    }

    func clearAll() {
        hasDispatchedWork = true
        queue.async {
            guard let db = self.openIfNeeded() else { return }

            let sql = "DELETE FROM conversion_log;"
            var errMsg: UnsafeMutablePointer<CChar>?
            if sqlite3_exec(db, sql, nil, nil, &errMsg) == SQLITE_OK {
                Log.logStore.info("Cleared all logs")
            }
            sqlite3_free(errMsg)
        }
    }

    // MARK: - Private Queue-Isolated Helpers

    private func openIfNeeded() -> OpaquePointer? {
        if let db {
            return db
        }

        let path: String
        if let customDatabaseURL {
            let dir = customDatabaseURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            path = customDatabaseURL.path
        } else {
            path = ConversionLogStore.defaultDatabasePath()
        }

        Log.logStore.debug("Opening database at \(path, privacy: .private)")

        var handle: OpaquePointer?
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let err = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            Log.logStore.error("Failed to open database: \(err, privacy: .public)")
            if let handle {
                sqlite3_close(handle)
            }
            return nil
        }

        guard let handle else { return nil }
        db = handle
        createTableIfNeeded(db: handle)
        return handle
    }

    private func createTableIfNeeded(db: OpaquePointer) {
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

    private func fetchAll(db: OpaquePointer) -> [ConversionLog] {
        let sql =
            "SELECT id, timestamp, input_text, output_text, source_layout, target_layout, conversion_mode, is_correct FROM conversion_log ORDER BY timestamp DESC;"

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            Log.logStore.error("Failed to prepare SELECT")
            return []
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
        return results
    }
}
