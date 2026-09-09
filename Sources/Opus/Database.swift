import Foundation
import CSQLite

enum StorageError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(message) = self { return message }; return nil }
}

// All access is serialized by Store on the main actor. Writes are small and transactional.
final class Database {
    private var handle: OpaquePointer?
    let url: URL
    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard sqlite3_open(url.path, &handle) == SQLITE_OK else { throw StorageError.message("Could not open database.") }
        sqlite3_busy_timeout(handle, 3000)
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
        let version = Int(try rows("PRAGMA user_version").first ?? "0") ?? 0
        guard version <= 2 else { throw StorageError.message("This database needs a newer version of Opus.") }
        // Typed JSON payloads allow optional tracker fields to evolve, with relational IDs and constraints.
        try execute("""
        BEGIN;
        CREATE TABLE IF NOT EXISTS courses (id TEXT PRIMARY KEY, payload TEXT NOT NULL, position INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, course_id TEXT REFERENCES courses(id) ON DELETE SET NULL, payload TEXT NOT NULL, position INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS assessments (id TEXT PRIMARY KEY, course_id TEXT REFERENCES courses(id) ON DELETE SET NULL, payload TEXT NOT NULL, position INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS rules (id TEXT PRIMARY KEY, course_id TEXT REFERENCES courses(id) ON DELETE SET NULL, payload TEXT NOT NULL, position INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS activities (id TEXT PRIMARY KEY, task_id TEXT NOT NULL REFERENCES tasks(id) ON DELETE CASCADE, payload TEXT NOT NULL, position INTEGER NOT NULL);
        CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE IF NOT EXISTS schedule (id TEXT PRIMARY KEY, course_id TEXT REFERENCES courses(id) ON DELETE SET NULL, payload TEXT NOT NULL, position INTEGER NOT NULL);
        PRAGMA user_version = 2;
        COMMIT;
        """)
    }
    deinit { sqlite3_close(handle) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
            throw StorageError.message(String(cString: sqlite3_errmsg(handle)))
        }
    }
    private func statement(_ sql: String, values: [String?] = []) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw StorageError.message(String(cString: sqlite3_errmsg(handle)))
        }
        for (index, value) in values.enumerated() {
            if let value {
                let result = value.withCString { sqlite3_bind_text(stmt, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                if result != SQLITE_OK { sqlite3_finalize(stmt); throw StorageError.message("Could not bind database value.") }
            } else { sqlite3_bind_null(stmt, Int32(index + 1)) }
        }
        return stmt
    }
    private func write(_ sql: String, _ values: [String?]) throws {
        let stmt = try statement(sql, values: values)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw StorageError.message(String(cString: sqlite3_errmsg(handle))) }
    }
    private func rows(_ sql: String) throws -> [String] {
        let stmt = try statement(sql)
        defer { sqlite3_finalize(stmt) }
        var result: [String] = []
        while true {
            let status = sqlite3_step(stmt)
            if status == SQLITE_DONE { break }
            guard status == SQLITE_ROW, let value = sqlite3_column_text(stmt, 0) else { throw StorageError.message("Could not read database.") }
            result.append(String(cString: value))
        }
        return result
    }
    private func decode<T: Decodable>(_ table: String) throws -> [T] {
        try rows("SELECT payload FROM \(table) ORDER BY position").map { try JSONDecoder().decode(T.self, from: Data($0.utf8)) }
    }
    func load() throws -> Snapshot {
        var state = Snapshot()
        state.courses = try decode("courses")
        state.tasks = try decode("tasks")
        state.assessments = try decode("assessments")
        state.rules = try decode("rules")
        state.schedule = try decode("schedule")
        state.activities = try decode("activities")
        state.setupComplete = try rows("SELECT value FROM metadata WHERE key = 'setup'").first == "true"
        if let generated = try rows("SELECT value FROM metadata WHERE key = 'generated'").first {
            state.generated = try JSONDecoder().decode(Set<String>.self, from: Data(generated.utf8))
        }
        return state
    }
    func save(_ state: Snapshot) throws {
        let encoder = JSONEncoder()
        func json<T: Encodable>(_ value: T) throws -> String { String(decoding: try encoder.encode(value), as: UTF8.self) }
        try execute("BEGIN IMMEDIATE")
        do {
            for table in ["activities", "tasks", "assessments", "rules", "schedule", "courses", "metadata"] { try execute("DELETE FROM \(table)") }
            for (i, item) in state.courses.enumerated() {
                try write("INSERT INTO courses VALUES (?, ?, ?)", [item.id, try json(item), String(i)])
            }
            for (i, item) in state.tasks.enumerated() {
                try write("INSERT INTO tasks VALUES (?, ?, ?, ?)", [item.id, item.courseID, try json(item), String(i)])
            }
            for (i, item) in state.assessments.enumerated() {
                try write("INSERT INTO assessments VALUES (?, ?, ?, ?)", [item.id, item.courseID, try json(item), String(i)])
            }
            for (i, item) in state.rules.enumerated() {
                try write("INSERT INTO rules VALUES (?, ?, ?, ?)", [item.id, item.courseID, try json(item), String(i)])
            }
            for (i, item) in state.schedule.enumerated() {
                try write("INSERT INTO schedule VALUES (?, ?, ?, ?)", [item.id, item.courseID, try json(item), String(i)])
            }
            for (i, item) in state.activities.enumerated() {
                try write("INSERT INTO activities VALUES (?, ?, ?, ?)", [item.id, item.taskID, try json(item), String(i)])
            }
            try write("INSERT INTO metadata VALUES ('setup', ?)", [state.setupComplete ? "true" : "false"])
            try write("INSERT INTO metadata VALUES ('generated', ?)", [try json(state.generated)])
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
}
