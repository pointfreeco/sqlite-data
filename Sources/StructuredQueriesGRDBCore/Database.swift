import Foundation
import GRDB
import IssueReporting
import SQLite3
import StructuredQueriesCore

struct Database {
  private let db: GRDB.Database
  private let handle: OpaquePointer

  init(_ handle: OpaquePointer, db: GRDB.Database) {
    self.db = db
    self.handle = handle
  }

  public func execute(
    _ sql: String
  ) throws {
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK
    else {
      throw SQLiteError(handle)
    }
  }

  public func execute(_ query: some StructuredQueriesCore.Statement<()>) throws {
    _ = try execute(query) as [()]
  }

  public func execute<QueryValue: QueryRepresentable>(
    _ query: some StructuredQueriesCore.Statement<QueryValue>
  ) throws -> [QueryValue.QueryOutput] {
    let query = query.query
    guard !query.isEmpty else {
      reportIssue("Can't fetch from empty query")
      return []
    }
    return try withStatement(query) { statement in
      var results: [QueryValue.QueryOutput] = []
      var decoder = SQLiteQueryDecoder(database: handle, statement: statement)
      loop: while true {
        let code = sqlite3_step(statement)
        switch code {
        case SQLITE_ROW:
          try results.append(decoder.decodeColumns(QueryValue.self))
          decoder.next()
        case SQLITE_DONE:
          break loop
        default:
          throw SQLiteError(handle)
        }
      }
      return results
    }
  }

  public func execute<each V: QueryRepresentable>(
    _ query: some StructuredQueriesCore.Statement<(repeat each V)>
  ) throws -> [(repeat (each V).QueryOutput)] {
    let query = query.query
    guard !query.isEmpty else {
      reportIssue("Can't fetch from empty query")
      return []
    }
    return try withStatement(query) { statement in
      var results: [(repeat (each V).QueryOutput)] = []
      var decoder = SQLiteQueryDecoder(database: handle, statement: statement)
      loop: while true {
        let code = sqlite3_step(statement)
        switch code {
        case SQLITE_ROW:
          try results.append(decoder.decodeColumns((repeat each V).self))
          decoder.next()
        case SQLITE_DONE:
          break loop
        default:
          throw SQLiteError(handle)
        }
      }
      return results
    }
  }

  public func execute<S: SelectStatement, each J: StructuredQueriesCore.Table>(
    _ query: S
  ) throws -> [(S.From.QueryOutput, repeat (each J).QueryOutput)]
  where S.QueryValue == (), S.Joins == (repeat each J) {
    let query = query.query
    guard !query.isEmpty else {
      reportIssue("Can't fetch from empty query")
      return []
    }
    return try withStatement(query) { statement in
      var results: [(S.From.QueryOutput, repeat (each J).QueryOutput)] = []
      var decoder = SQLiteQueryDecoder(database: handle, statement: statement)
      loop: while true {
        let code = sqlite3_step(statement)
        switch code {
        case SQLITE_ROW:
          try results.append(
            (
              decoder.decodeColumns(S.From.self),
              repeat decoder.decodeColumns((each J).self)
            )
          )
          decoder.next()
        case SQLITE_DONE:
          break loop
        default:
          throw SQLiteError(handle)
        }
      }
      return results
    }
  }

  private func withStatement<R>(
    _ query: QueryFragment, body: (OpaquePointer) throws -> R
  ) throws -> R {
    let statement = try db.makeStatement(sql: query.string)
    try db.registerAccess(to: statement.databaseRegion)
    for (index, binding) in zip(Int32(1)..., query.bindings) {
      let result =
        switch binding {
        case let .blob(blob):
          sqlite3_bind_blob(
            statement.sqliteStatement, index, Array(blob), Int32(blob.count), SQLITE_TRANSIENT
          )
        case let .double(double):
          sqlite3_bind_double(statement.sqliteStatement, index, double)
        case let .int(int):
          sqlite3_bind_int64(statement.sqliteStatement, index, Int64(int))
        case .null:
          sqlite3_bind_null(statement.sqliteStatement, index)
        case let .text(text):
          sqlite3_bind_text(statement.sqliteStatement, index, text, -1, SQLITE_TRANSIENT)
        }
      guard result == SQLITE_OK else { throw SQLiteError(handle) }
    }
    let results = try body(statement.sqliteStatement)
    try db.notifyChanges(in: statement.databaseRegion)
    return results
  }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct SQLiteError: Error {
  let message: String

  init(_ handle: OpaquePointer?) {
    self.message = String(cString: sqlite3_errmsg(handle))
  }
}
