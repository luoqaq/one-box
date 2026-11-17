import Foundation
import SQLite3

/// 极薄 SQLite3 封装：打开、执行、预编译语句。
/// 仅服务 ClipboardStore/CaptureStore，不追求通用。
final class SQLiteDatabase {
    private var handle: OpaquePointer?

    enum SQLiteError: Error, CustomStringConvertible {
        case open(Int32, String)
        case prepare(String, String)
        case step(String, String)
        case exec(String, String)

        var description: String {
            switch self {
            case let .open(code, msg): return "sqlite open failed (\(code)): \(msg)"
            case let .prepare(sql, msg): return "sqlite prepare failed [\(sql)]: \(msg)"
            case let .step(sql, msg): return "sqlite step failed [\(sql)]: \(msg)"
            case let .exec(sql, msg): return "sqlite exec failed [\(sql)]: \(msg)"
            }
        }
    }

    init(path: String) throws {
        var db: OpaquePointer?
        let rc = sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let db else {
            let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close_v2(db)
            throw SQLiteError.open(rc, msg)
        }
        self.handle = db
    }

    deinit { sqlite3_close_v2(handle) }

    func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(handle, sql, nil, nil, &err)
        guard rc == SQLITE_OK else {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw SQLiteError.exec(sql, msg)
        }
    }

    /// 预编译并运行一个语句。bind 按 1-based 顺序。
    /// row 回调在每行 step==ROW 时调用；返回 true 继续遍历。
    func run(
        _ sql: String,
        bind: (Statement) -> Void = { _ in },
        row: (Statement) -> Void = { _ in }
    ) throws {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt.handle) }
        bind(stmt)
        while true {
            let rc = sqlite3_step(stmt.handle)
            if rc == SQLITE_ROW {
                row(stmt)
                continue
            }
            if rc == SQLITE_DONE { break }
            throw SQLiteError.step(sql, String(cString: sqlite3_errmsg(handle)))
        }
    }

    private func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw SQLiteError.prepare(sql, String(cString: sqlite3_errmsg(handle)))
        }
        return Statement(handle: stmt)
    }

    struct Statement {
        let handle: OpaquePointer?

        // Bind
        func bindText(_ idx: Int32, _ value: String?) {
            if let value {
                sqlite3_bind_text(handle, idx, value, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(handle, idx)
            }
        }
        func bindInt(_ idx: Int32, _ value: Int64?) {
            if let value { sqlite3_bind_int64(handle, idx, value) } else { sqlite3_bind_null(handle, idx) }
        }
        func bindDouble(_ idx: Int32, _ value: Double) {
            sqlite3_bind_double(handle, idx, value)
        }

        // Column
        func text(_ idx: Int32) -> String? {
            guard let cString = sqlite3_column_text(handle, idx) else { return nil }
            return String(cString: cString)
        }
        func int(_ idx: Int32) -> Int64 {
            sqlite3_column_int64(handle, idx)
        }
        func double(_ idx: Int32) -> Double {
            sqlite3_column_double(handle, idx)
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
