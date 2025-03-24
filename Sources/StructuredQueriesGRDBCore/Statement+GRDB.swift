import GRDB
import SQLite3
import StructuredQueriesCore

extension StructuredQueriesCore.Statement {
  public func execute(_ db: Database) throws where QueryValue == () {
    try QueryVoidCursor(db: db, query: query).next()
  }

  public func fetchAll(_ db: Database) throws -> [QueryValue.QueryOutput]
  where QueryValue: QueryRepresentable {
    try Array(fetchCursor(db))
  }

  public func fetchOne(_ db: Database) throws -> QueryValue.QueryOutput?
  where QueryValue: QueryRepresentable {
    try fetchCursor(db).next()
  }

  public func fetchCursor(_ db: Database) throws -> QueryCursor<QueryValue.QueryOutput>
  where QueryValue: QueryRepresentable {
    try QueryValueCursor<QueryValue>(db: db, query: query)
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension StructuredQueriesCore.Statement {
  public func fetchAll<each Value: QueryRepresentable>(
    _ db: Database
  ) throws -> [(repeat (each Value).QueryOutput)]
  where QueryValue == (repeat each Value) {
    let cursor = try fetchCursor(db)
    return try Array(cursor)
  }

  public func fetchOne<each Value: QueryRepresentable>(
    _ db: Database
  ) throws -> (repeat (each Value).QueryOutput)?
  where QueryValue == (repeat each Value) {
    let cursor = try fetchCursor(db)
    return try cursor.next()
  }

  public func fetchCursor<each Value: QueryRepresentable>(
    _ db: Database
  ) throws -> QueryCursor<(repeat (each Value).QueryOutput)>
  where QueryValue == (repeat each Value) {
    try QueryPackCursor<repeat each Value>(db: db, query: query)
  }
}

extension SelectStatement where QueryValue == (), Joins == () {
  public func fetchAll(_ db: Database) throws -> [From.QueryOutput] {
    let query = selectStar()
    return try query.fetchAll(db)
  }

  public func fetchOne(_ db: Database) throws -> From.QueryOutput? {
    let query = selectStar()
    return try query.fetchOne(db)
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SelectStatement where QueryValue == () {
  public func fetchAll<each J: StructuredQueriesCore.Table>(
    _ db: Database
  ) throws -> [(From.QueryOutput, repeat (each J).QueryOutput)]
  where Joins == (repeat each J) {
    try selectStar().fetchAll(db)
  }

  public func fetchOne<each J: StructuredQueriesCore.Table>(
    _ db: Database
  ) throws -> (From.QueryOutput, repeat (each J).QueryOutput)?
  where Joins == (repeat each J) {
    try selectStar().fetchOne(db)
  }
}
