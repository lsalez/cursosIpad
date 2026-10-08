// SearchIndexDatabase.swift
//
// Thin wrapper over the C SQLite API for the cursosIpad FTS5 search
// index. One instance per app session, one underlying connection,
// held by the `SearchIndexer` actor so all access is serialized.
//
// We talk to SQLite directly instead of pulling in GRDB or SQLite.swift
// because:
//
//   * The project explicitly forbids new dependencies (CLAUDE.md).
//   * Our needs are narrow: open a connection, prepare a handful of
//     statements, bind values, step, finalize. The C API is verbose
//     but entirely tractable for that.
//   * FTS5 is built into the system libsqlite3 on iOS, so no extra
//     linker steps are required.
//
// Schema lives in `schema()` at the bottom of the file. The
// `tokenize` option is the single most important knob: it
// determines how user input is broken into search terms. We use
// `unicode61` with `remove_diacritics=2` and `categories='L* N* Co'`
// so searches in Spanish work without tildes ("decoración" matches
// "decoracion"). The fallback when the simulator's SQLite version
// doesn't support `remove_diacritics=2` is to downgrade to
// `remove_diacritics=1` (still strips accents, just doesn't fold
// some diacritics).
//
// Threading: a `sqlite3 *` connection is NOT thread-safe by
// default. The `SearchIndexer` actor guarantees serialized access.
// Don't call into this class from multiple threads concurrently.
//
// Resources: every `sqlite3_stmt *` returned by `sqlite3_prepare_v2`
// is owned and finalized. We pre-compile statements we use a lot
// (`insert`, `selectByKind`, `deleteByLesson`, `mtimeLookup`,
// `mtimeRecord`) in `prepareStatements()` and re-bind on each
// invocation. Statements we use once (schema creation, single-shot
// pragma) are prepared and finalized inline.

import Foundation
import SQLite3

public final class SearchIndexDatabase {

    // SQLite uses these sentinels in place of `bool`.
    // `SQLITE_STATIC == 0` (null destructor — the buffer must outlive
    // the binding) and `SQLITE_TRANSIENT == -1` (a magic value
    // telling SQLite to make its own copy of the bytes). Both are
    // commonly expressed via `unsafeBitCast` from the corresponding
    // integer — that's the canonical Swift idiom for SQLite
    // sentinel values.
    private static let SQLITE_STATIC = unsafeBitCast(
        Int(0), to: sqlite3_destructor_type.self
    )
    private static let SQLITE_TRANSIENT = unsafeBitCast(
        Int(-1), to: sqlite3_destructor_type.self
    )

    public enum Kind: String, Sendable {
        case subtitle
        case html
    }

    /// One row from a successful search. `snippetRaw` contains
    /// `<<`/`>>` delimiters around the matched text as configured in
    /// the SQL `snippet()` call. `rank` is the FTS5 BM25 score
    /// (lower is better — SQLite's default).
    public struct SearchHit: Sendable, Equatable {
        public let courseKey: String
        public let courseTitle: String
        public let lessonPath: String
        public let kind: Kind
        public let startSeconds: Double?
        public let paragraphIndex: Int?
        public let snippetRaw: String
        public let rank: Double

        public init(
            courseKey: String,
            courseTitle: String,
            lessonPath: String,
            kind: Kind,
            startSeconds: Double?,
            paragraphIndex: Int?,
            snippetRaw: String,
            rank: Double
        ) {
            self.courseKey = courseKey
            self.courseTitle = courseTitle
            self.lessonPath = lessonPath
            self.kind = kind
            self.startSeconds = startSeconds
            self.paragraphIndex = paragraphIndex
            self.snippetRaw = snippetRaw
            self.rank = rank
        }
    }

    /// A file we need to consider for indexing. The orchestrator
    /// builds a list of these for every indexable file on disk and
    /// hands it to `filesToReindex(onDisk:)` for the diff against
    /// the `indexed_files` metadata table.
    public struct FileOnDisk: Sendable, Equatable {
        public let courseKey: String
        public let courseTitle: String
        public let lessonPath: String
        public let kind: Kind
        public let mtime: Int64

        public init(
            courseKey: String,
            courseTitle: String,
            lessonPath: String,
            kind: Kind,
            mtime: Int64
        ) {
            self.courseKey = courseKey
            self.courseTitle = courseTitle
            self.lessonPath = lessonPath
            self.kind = kind
            self.mtime = mtime
        }
    }

    public enum DatabaseError: Error, LocalizedError {
        case open(Int32, String)
        case prepare(String, String)
        case step(String, String)
        case bind(String, String)
        case exec(String, String)

        public var errorDescription: String? {
            switch self {
            case let .open(code, message):
                return "SQLite open failed (\(code)): \(message)"
            case let .prepare(sql, message):
                return "SQLite prepare failed for [\(sql)]: \(message)"
            case let .step(sql, message):
                return "SQLite step failed for [\(sql)]: \(message)"
            case let .bind(sql, message):
                return "SQLite bind failed for [\(sql)]: \(message)"
            case let .exec(sql, message):
                return "SQLite exec failed for [\(sql)]: \(message)"
            }
        }
    }

    // MARK: - State

    private var db: OpaquePointer?
    private let url: URL

    // Prepared statements. Recreated on every `prepareStatements()`.
    private var stmtInsert: OpaquePointer?
    private var stmtDeleteByLesson: OpaquePointer?
    private var stmtMtimeLookup: OpaquePointer?
    private var stmtMtimeRecord: OpaquePointer?

    // MARK: - Init

    public init(fileURL: URL) throws {
        self.url = fileURL
        try open()
        try applyPragmas()
        try createSchema()
        try prepareStatements()
    }

    deinit {
        finalizeStatements()
        if let db {
            sqlite3_close(db)
        }
    }

    public func close() {
        finalizeStatements()
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    // MARK: - Schema

    /// Apply PRAGMAs that make the index robust for our use case.
    /// `journal_mode=WAL` lets readers and one writer coexist, so the
    /// UI can query while the indexer is bulk-loading. WAL also
    /// reduces fsync cost. `synchronous=NORMAL` is the recommended
    /// pairing: durable enough for our use (local app data, no
    /// server), and much faster than `FULL` for inserts.
    private func applyPragmas() throws {
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA synchronous=NORMAL;")
        try exec("PRAGMA foreign_keys=ON;")
    }

    /// Create the FTS5 virtual table and the metadata table that
    /// powers the incremental-by-mtime diff. `IF NOT EXISTS` makes
    /// this safe to call on every launch.
    ///
    /// The tokenize string is the most fragile part: the iOS
    /// simulator's SQLite (3.54.0 at time of writing) **only
    /// accepts the space-separated form** of `remove_diacritics N`
    /// (the `=` form, documented in some references, is not
    /// recognized). We try `remove_diacritics 2` first (best Spanish
    /// behavior); on failure we log a warning and fall back to
    /// `remove_diacritics 1`.
    ///
    /// We rely on the FTS5 `unicode61` defaults for `categories` —
    /// the default (`'L* N* Co Mn'`) is already what we want for
    /// Spanish text, so we don't override it. Overriding it requires
    /// a nested single-quote-escape inside the SQL string, which is
    /// a frequent source of bugs.
    private func createSchema() throws {
        let primaryTokenize = "unicode61 remove_diacritics 2"
        let fallbackTokenize = "unicode61 remove_diacritics 1"
        let ddl = """
        CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
            course_key UNINDEXED,
            course_title UNINDEXED,
            lesson_path UNINDEXED,
            kind UNINDEXED,
            start_seconds UNINDEXED,
            paragraph_index UNINDEXED,
            text,
            tokenize='\(primaryTokenize)'
        );
        """
        do {
            try exec(ddl)
        } catch {
            print("[SearchIndexDatabase] primary tokenize failed, falling back: \(error)")
            let fallback = """
            CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
                course_key UNINDEXED,
                course_title UNINDEXED,
                lesson_path UNINDEXED,
                kind UNINDEXED,
                start_seconds UNINDEXED,
                paragraph_index UNINDEXED,
                text,
                tokenize='\(fallbackTokenize)'
            );
            """
            try exec(fallback)
        }
        try exec("""
        CREATE TABLE IF NOT EXISTS indexed_files (
            course_key TEXT NOT NULL,
            lesson_path TEXT NOT NULL,
            kind TEXT NOT NULL,
            mtime INTEGER NOT NULL,
            PRIMARY KEY (course_key, lesson_path, kind)
        );
        """)
    }

    private func prepareStatements() throws {
        try prepare(
            &stmtInsert,
            sql: """
            INSERT INTO search_index
                (course_key, course_title, lesson_path, kind, start_seconds, paragraph_index, text)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
        )
        try prepare(
            &stmtDeleteByLesson,
            sql: """
            DELETE FROM search_index
            WHERE course_key = ? AND lesson_path = ? AND kind = ?;
            """
        )
        try prepare(
            &stmtMtimeLookup,
            sql: """
            SELECT mtime FROM indexed_files
            WHERE course_key = ? AND lesson_path = ? AND kind = ?;
            """
        )
        try prepare(
            &stmtMtimeRecord,
            sql: """
            INSERT OR REPLACE INTO indexed_files
                (course_key, lesson_path, kind, mtime)
            VALUES (?, ?, ?, ?);
            """
        )
    }

    private func finalizeStatements() {
        if let stmtInsert { sqlite3_finalize(stmtInsert); self.stmtInsert = nil }
        if let stmtDeleteByLesson { sqlite3_finalize(stmtDeleteByLesson); self.stmtDeleteByLesson = nil }
        if let stmtMtimeLookup { sqlite3_finalize(stmtMtimeLookup); self.stmtMtimeLookup = nil }
        if let stmtMtimeRecord { sqlite3_finalize(stmtMtimeRecord); self.stmtMtimeRecord = nil }
    }

    // MARK: - Indexing API

    /// Insert one row into the FTS5 index. The `text` column is
    /// tokenized on insert; everything else is `UNINDEXED` and
    /// stored as-is. `startSeconds` and `paragraphIndex` are
    /// optional (only one is set per row, depending on `kind`).
    public func insert(
        courseKey: String,
        courseTitle: String,
        lessonPath: String,
        kind: Kind,
        startSeconds: Double?,
        paragraphIndex: Int?,
        text: String
    ) throws {
        guard let stmt = stmtInsert else {
            throw DatabaseError.prepare("insert", "statement not prepared")
        }
        sqlite3_reset(stmt)
        bindText(stmt, index: 1, value: courseKey)
        bindText(stmt, index: 2, value: courseTitle)
        bindText(stmt, index: 3, value: lessonPath)
        bindText(stmt, index: 4, value: kind.rawValue)
        if let startSeconds {
            sqlite3_bind_double(stmt, 5, startSeconds)
        } else {
            sqlite3_bind_null(stmt, 5)
        }
        if let paragraphIndex {
            sqlite3_bind_int64(stmt, 6, Int64(paragraphIndex))
        } else {
            sqlite3_bind_null(stmt, 6)
        }
        bindText(stmt, index: 7, value: text)
        let code = sqlite3_step(stmt)
        if code != SQLITE_DONE && code != SQLITE_ROW {
            let msg = lastErrorMessage()
            throw DatabaseError.step("insert", msg)
        }
        sqlite3_clear_bindings(stmt)
        sqlite3_reset(stmt)
    }

    /// Delete every row for a (course, lesson, kind) tuple. Called
    /// before re-indexing a file so the new content fully replaces
    /// the old. Safe to call when the tuple doesn't exist (no-op).
    public func deleteAllForLesson(courseKey: String, lessonPath: String, kind: Kind) throws {
        guard let stmt = stmtDeleteByLesson else {
            throw DatabaseError.prepare("deleteByLesson", "statement not prepared")
        }
        sqlite3_reset(stmt)
        bindText(stmt, index: 1, value: courseKey)
        bindText(stmt, index: 2, value: lessonPath)
        bindText(stmt, index: 3, value: kind.rawValue)
        try step(stmt, label: "deleteByLesson")
    }

    /// Look up the `mtime` of a previously-indexed file. Returns
    /// `nil` if the file has never been indexed.
    public func mtime(courseKey: String, lessonPath: String, kind: Kind) throws -> Int64? {
        guard let stmt = stmtMtimeLookup else {
            throw DatabaseError.prepare("mtimeLookup", "statement not prepared")
        }
        sqlite3_reset(stmt)
        bindText(stmt, index: 1, value: courseKey)
        bindText(stmt, index: 2, value: lessonPath)
        bindText(stmt, index: 3, value: kind.rawValue)
        let result = sqlite3_step(stmt)
        if result == SQLITE_ROW {
            return sqlite3_column_int64(stmt, 0)
        }
        if result == SQLITE_DONE {
            return nil
        }
        throw DatabaseError.step("mtimeLookup", lastErrorMessage())
    }

    /// Persist the mtime we just indexed a file with. Used so the
    /// next diff knows whether the file changed.
    public func recordMTime(courseKey: String, lessonPath: String, kind: Kind, mtime: Int64) throws {
        guard let stmt = stmtMtimeRecord else {
            throw DatabaseError.prepare("mtimeRecord", "statement not prepared")
        }
        sqlite3_reset(stmt)
        bindText(stmt, index: 1, value: courseKey)
        bindText(stmt, index: 2, value: lessonPath)
        bindText(stmt, index: 3, value: kind.rawValue)
        sqlite3_bind_int64(stmt, 4, mtime)
        try step(stmt, label: "mtimeRecord")
    }

    /// Filter `onDisk` to entries whose `(course_key, lesson_path, kind)`
    /// is new or whose `mtime` differs from the stored value. This
    /// is the core of the incremental-by-mtime logic.
    public func filesToReindex(onDisk: [FileOnDisk]) throws -> [FileOnDisk] {
        var toReindex: [FileOnDisk] = []
        for file in onDisk {
            let stored = try mtime(
                courseKey: file.courseKey,
                lessonPath: file.lessonPath,
                kind: file.kind
            )
            if stored != file.mtime {
                toReindex.append(file)
            }
        }
        return toReindex
    }

    /// Return the set of `course_key` values that were once in the
    /// index but no longer appear in `currentKeys`. The orchestrator
    /// uses this to drop rows for deleted courses.
    public func detectDeletedCourseKeys(currentKeys: Set<String>) throws -> [String] {
        let sql = "SELECT DISTINCT course_key FROM search_index;"
        var stmt: OpaquePointer?
        try prepare(&stmt, sql: sql)
        defer { sqlite3_finalize(stmt) }
        var found: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                found.insert(String(cString: cString))
            }
        }
        return Array(found.subtracting(currentKeys))
    }

    /// Delete every row (and mtime record) for one course. Called
    /// when a course has been removed from disk.
    public func deleteAllForCourse(courseKey: String) throws {
        try execBind("DELETE FROM search_index WHERE course_key = ?;", courseKey)
        try execBind("DELETE FROM indexed_files WHERE course_key = ?;", courseKey)
    }

    // MARK: - Search

    /// Run an FTS5 `MATCH` query and return up to `limit` hits
    /// ordered by rank. The `snippet()` SQL function builds a
    /// ~12-token window around the match and surrounds the matched
    /// span with `<<`/`>>` delimiters. The caller (the actor) is
    /// responsible for turning those delimiters into a styled
    /// `AttributedString` for display.
    ///
    /// Caller is also responsible for any FTS5 query syntax (the
    /// `?` here is bound as a single MATCH expression). For
    /// multi-word user input, the actor wraps each token in double
    /// quotes to keep SQLite from interpreting `AND`/`OR`/`NOT` as
    /// operators.
    public func search(query: String, limit: Int) throws -> [SearchHit] {
        let sql = """
        SELECT course_key, course_title, lesson_path, kind,
               start_seconds, paragraph_index,
               snippet(search_index, 7, '<<', '>>', '…', 12) AS snip,
               rank
        FROM search_index
        WHERE search_index MATCH ?
        ORDER BY rank
        LIMIT ?;
        """
        var stmt: OpaquePointer?
        try prepare(&stmt, sql: sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt!, index: 1, value: query)
        sqlite3_bind_int(stmt!, 2, Int32(limit))
        var hits: [SearchHit] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let courseKey = columnString(stmt!, 0)
            let courseTitle = columnString(stmt!, 1)
            let lessonPath = columnString(stmt!, 2)
            let kindRaw = columnString(stmt!, 3)
            let startSeconds: Double? = columnIsNull(stmt!, 4)
                ? nil
                : sqlite3_column_double(stmt!, 4)
            let paragraphIndex: Int? = columnIsNull(stmt!, 5)
                ? nil
                : Int(sqlite3_column_int64(stmt!, 5))
            let snippet = columnString(stmt!, 6)
            let rank = sqlite3_column_double(stmt!, 7)
            let kind = Kind(rawValue: kindRaw) ?? .html
            hits.append(
                SearchHit(
                    courseKey: courseKey,
                    courseTitle: courseTitle,
                    lessonPath: lessonPath,
                    kind: kind,
                    startSeconds: startSeconds,
                    paragraphIndex: paragraphIndex,
                    snippetRaw: snippet,
                    rank: rank
                )
            )
        }
        return hits
    }

    // MARK: - Low-level SQLite helpers

    private func open() throws {
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(url.path, &db, flags, nil)
        if code != SQLITE_OK {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let db { sqlite3_close(db) }
            self.db = nil
            throw DatabaseError.open(code, message)
        }
    }

    private func exec(_ sql: String) throws {
        var errMsgPtr: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(db, sql, nil, nil, &errMsgPtr)
        if code != SQLITE_OK {
            let message = errMsgPtr.map { String(cString: $0) } ?? "unknown"
            if let errMsgPtr { sqlite3_free(errMsgPtr) }
            throw DatabaseError.exec(sql, message)
        }
    }

    private func execBind(_ sql: String, _ value: String) throws {
        var stmt: OpaquePointer?
        try prepare(&stmt, sql: sql)
        defer { sqlite3_finalize(stmt) }
        bindText(stmt!, index: 1, value: value)
        try step(stmt!, label: "execBind")
    }

    private func prepare(_ target: inout OpaquePointer?, sql: String) throws {
        var stmt: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if code != SQLITE_OK {
            throw DatabaseError.prepare(sql, lastErrorMessage())
        }
        target = stmt
    }

    private func step(_ stmt: OpaquePointer?, label: String) throws {
        let code = sqlite3_step(stmt)
        if code != SQLITE_DONE && code != SQLITE_ROW {
            throw DatabaseError.step(label, lastErrorMessage())
        }
    }

    private func bindText(_ stmt: OpaquePointer?, index: Int32, value: String) {
        // SQLITE_TRANSIENT tells SQLite to copy the bytes, so the
        // Swift String can be released as soon as the call returns.
        let code = sqlite3_bind_text(
            stmt,
            index,
            value,
            -1,
            Self.SQLITE_TRANSIENT
        )
        if code != SQLITE_OK {
            // Bind errors are non-recoverable for the current step.
            // We log and let the subsequent `step` throw with the
            // real error so the caller still gets a useful message.
            print("[SearchIndexDatabase] bind_text failed (\(code)) for index \(index): \(lastErrorMessage())")
        }
    }

    private func columnString(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else {
            return ""
        }
        return String(cString: cString)
    }

    private func columnIsNull(_ stmt: OpaquePointer?, _ index: Int32) -> Bool {
        sqlite3_column_type(stmt, index) == SQLITE_NULL
    }

    private func lastErrorMessage() -> String {
        guard let db, let cString = sqlite3_errmsg(db) else {
            return "unknown"
        }
        return String(cString: cString)
    }
}
