import Foundation
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
    _statement.arguments = StatementArguments(query.bindings.map(\.databaseValue))
    decoder = SQLiteQueryDecoder(
      database: db.sqliteConnection,
      statement: _statement.sqliteStatement
    )
  }

  deinit {
    sqlite3_reset(_statement.sqliteStatement)
  }

  public func _element(sqliteStatement _: SQLiteStatement) throws -> Element {
    let element = try decoder.decodeColumns((repeat each QueryValue).self)
    decoder.next()
    return element
  }

  private struct EmptyQuery: Error {}
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

extension QueryBinding {
  fileprivate var databaseValue: DatabaseValue {
    switch self {
    case let .blob(blob):
      return Data(blob).databaseValue
    case let .double(double):
      return double.databaseValue
    case let .int(int):
      return int.databaseValue
    case .null:
      return .null
    case let .text(text):
      return text.databaseValue
    }
  }
}
