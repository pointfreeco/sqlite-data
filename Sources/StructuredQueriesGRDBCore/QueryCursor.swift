import GRDB
import SQLite3
import StructuredQueriesCore

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
public final class QueryCursor<each QueryValue: QueryRepresentable>: DatabaseCursor {
  public typealias Element = (repeat (each QueryValue).QueryOutput)

  public var _isDone = false
  public let _statement: GRDB.Statement

  private var decoder: SQLiteQueryDecoder

  init(
    db: GRDB.Database,
    query: some StructuredQueriesCore.Statement<(repeat each QueryValue)>
  ) throws {
    let query = query.query
    guard !query.isEmpty else { throw EmptyQuery() }
    _statement = try db.makeStatement(sql: query.string)
    decoder = SQLiteQueryDecoder(
      database: db.sqliteConnection,
      statement: _statement.sqliteStatement
    )
    for (index, binding) in zip(Int32(1)..., query.bindings) {
      let result =
        switch binding {
        case let .blob(blob):
          sqlite3_bind_blob(
            _statement.sqliteStatement, index, Array(blob), Int32(blob.count), SQLITE_TRANSIENT
          )
        case let .double(double):
          sqlite3_bind_double(_statement.sqliteStatement, index, double)
        case let .int(int):
          sqlite3_bind_int64(_statement.sqliteStatement, index, Int64(int))
        case .null:
          sqlite3_bind_null(_statement.sqliteStatement, index)
        case let .text(text):
          sqlite3_bind_text(_statement.sqliteStatement, index, text, -1, SQLITE_TRANSIENT)
        }
      guard result == SQLITE_OK else { throw SQLiteError(db.sqliteConnection) }
    }
  }

  public func _element(sqliteStatement _: SQLiteStatement) throws -> Element {
    let element = try decoder.decodeColumns((repeat each QueryValue).self)
    decoder.next()
    return element
  }

  private struct EmptyQuery: Error {}
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct SQLiteError: Error {
  let message: String

  init(_ handle: OpaquePointer?) {
    self.message = String(cString: sqlite3_errmsg(handle))
  }
}
