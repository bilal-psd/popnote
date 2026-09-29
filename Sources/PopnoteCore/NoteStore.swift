import Foundation
import SQLite3

public enum StoreError: Error {
    case sqlite(String)
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// All notes, in one SQLite table. Active notes have `deleted_at` NULL;
/// notes in Trash have it set.
public final class NoteStore {
    private var db: OpaquePointer?

    /// Default location: ~/Library/Application Support/Popnote/popnote.sqlite
    public static func defaultURL() throws -> URL {
        let dir = try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Popnote", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("popnote.sqlite")
    }

    /// Pass nil for an in-memory database (tests).
    public init(url: URL?) throws {
        let path = url?.path ?? ":memory:"
        guard sqlite3_open(path, &db) == SQLITE_OK else {
            throw StoreError.sqlite("could not open \(path)")
        }
        try exec("""
            PRAGMA journal_mode = WAL;
            CREATE TABLE IF NOT EXISTS notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                body TEXT NOT NULL,
                created_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                pinned INTEGER NOT NULL DEFAULT 0,
                deleted_at REAL
            );
            CREATE INDEX IF NOT EXISTS notes_deleted_at ON notes(deleted_at);
            """)
    }

    deinit { sqlite3_close(db) }

    // MARK: Queries

    /// Active notes, oldest first. The newest note is last.
    public func activeNotes() throws -> [Note] {
        try query("SELECT * FROM notes WHERE deleted_at IS NULL ORDER BY created_at, id")
    }

    /// Notes in Trash, most recently deleted first.
    public func trashedNotes() throws -> [Note] {
        try query("SELECT * FROM notes WHERE deleted_at IS NOT NULL ORDER BY deleted_at DESC, id DESC")
    }

    public func note(id: Int64) throws -> Note? {
        try query("SELECT * FROM notes WHERE id = ?", [.int(id)]).first
    }

    // MARK: Writes

    @discardableResult
    public func insert(body: String, now: Date = Date()) throws -> Note {
        try run("INSERT INTO notes (body, created_at, updated_at) VALUES (?, ?, ?)",
                [.text(body), .date(now), .date(now)])
        return Note(id: sqlite3_last_insert_rowid(db), body: body, createdAt: now, updatedAt: now)
    }

    public func updateBody(id: Int64, body: String, now: Date = Date()) throws {
        try run("UPDATE notes SET body = ?, updated_at = ? WHERE id = ?", [.text(body), .date(now), .int(id)])
    }

    /// Unpinning restarts the expiry clock, so a note pinned long ago doesn't
    /// vanish on the next sweep.
    public func setPinned(id: Int64, _ pinned: Bool, now: Date = Date()) throws {
        if pinned {
            try run("UPDATE notes SET pinned = 1 WHERE id = ?", [.int(id)])
        } else {
            try run("UPDATE notes SET pinned = 0, updated_at = ? WHERE id = ?", [.date(now), .int(id)])
        }
    }

    public func moveToTrash(id: Int64, now: Date = Date()) throws {
        try run("UPDATE notes SET deleted_at = ? WHERE id = ?", [.date(now), .int(id)])
    }

    /// Brings a note back from Trash. Its expiry clock restarts so it
    /// doesn't vanish again on the next sweep.
    public func restore(id: Int64, now: Date = Date()) throws {
        try run("UPDATE notes SET deleted_at = NULL, updated_at = ? WHERE id = ?", [.date(now), .int(id)])
    }

    /// Permanently removes one note. Used for blank notes, which skip Trash.
    public func purge(id: Int64) throws {
        try run("DELETE FROM notes WHERE id = ?", [.int(id)])
    }

    public func emptyTrash() throws {
        try run("DELETE FROM notes WHERE deleted_at IS NOT NULL")
    }

    /// Moves expired notes to Trash and permanently removes notes that
    /// have been in Trash longer than `trashRetention`. Blank expired notes
    /// are removed outright. Returns true if anything changed.
    @discardableResult
    public func sweep(now: Date = Date(), ttl: TimeInterval, trashRetention: TimeInterval) throws -> Bool {
        var changed = false
        for note in try activeNotes() where Expiry.isExpired(note, now: now, ttl: ttl) {
            if note.isBlank {
                try purge(id: note.id)
            } else {
                try moveToTrash(id: note.id, now: now)
            }
            changed = true
        }
        let cutoff = now.addingTimeInterval(-trashRetention)
        try run("DELETE FROM notes WHERE deleted_at IS NOT NULL AND deleted_at <= ?", [.date(cutoff)])
        if sqlite3_changes(db) > 0 { changed = true }
        return changed
    }

    // MARK: SQLite plumbing

    private enum Value {
        case int(Int64), text(String), date(Date)
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw error() }
    }

    private func prepare(_ sql: String, _ values: [Value]) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw error() }
        for (i, value) in values.enumerated() {
            let idx = Int32(i + 1)
            switch value {
            case .int(let v): sqlite3_bind_int64(stmt, idx, v)
            case .text(let v): sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT)
            case .date(let v): sqlite3_bind_double(stmt, idx, v.timeIntervalSince1970)
            }
        }
        return stmt
    }

    private func run(_ sql: String, _ values: [Value] = []) throws {
        let stmt = try prepare(sql, values)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw error() }
    }

    private func query(_ sql: String, _ values: [Value] = []) throws -> [Note] {
        let stmt = try prepare(sql, values)
        defer { sqlite3_finalize(stmt) }
        var notes: [Note] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            notes.append(Note(
                id: sqlite3_column_int64(stmt, 0),
                body: String(cString: sqlite3_column_text(stmt, 1)),
                createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 2)),
                updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 3)),
                pinned: sqlite3_column_int(stmt, 4) != 0,
                deletedAt: sqlite3_column_type(stmt, 5) == SQLITE_NULL
                    ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 5))
            ))
        }
        return notes
    }

    private func error() -> StoreError {
        StoreError.sqlite(String(cString: sqlite3_errmsg(db)))
    }
}
