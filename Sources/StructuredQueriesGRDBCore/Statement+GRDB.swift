import GRDB
import SQLite3
import StructuredQueriesCore

extension StructuredQueriesCore.Statement {
  @inlinable
  public func execute(_ db: Database) throws where QueryValue == () {
    try QueryVoidCursor(db: db, query: query).next()
  }

  @inlinable
  public func fetchAll(_ db: Database) throws -> [QueryValue.QueryOutput]
  where QueryValue: QueryRepresentable {
    try Array(fetchCursor(db))
  }

  @inlinable
  public func fetchOne(_ db: Database) throws -> QueryValue.QueryOutput?
  where QueryValue: QueryRepresentable {
    try fetchCursor(db).next()
  }

  @inlinable
  public func fetchCursor(_ db: Database) throws -> QueryCursor<QueryValue.QueryOutput>
  where QueryValue: QueryRepresentable {
    try QueryValueCursor<QueryValue>(db: db, query: query)
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension StructuredQueriesCore.Statement {
  @inlinable
  public func fetchAll<each Value: QueryRepresentable>(
    _ db: Database
  ) throws -> [(repeat (each Value).QueryOutput)]
  where QueryValue == (repeat each Value) {
    let cursor = try fetchCursor(db)
    return try Array(cursor)
  }

  @inlinable
  public func fetchOne<each Value: QueryRepresentable>(
    _ db: Database
  ) throws -> (repeat (each Value).QueryOutput)?
  where QueryValue == (repeat each Value) {
    let cursor = try fetchCursor(db)
    return try cursor.next()
  }

  @inlinable
  public func fetchCursor<each Value: QueryRepresentable>(
    _ db: Database
  ) throws -> QueryCursor<(repeat (each Value).QueryOutput)>
  where QueryValue == (repeat each Value) {
    try QueryPackCursor<repeat each Value>(db: db, query: query)
  }
}

extension SelectStatement where QueryValue == (), Joins == () {
  @inlinable
  public func fetchCount(_ db: Database) throws -> Int {
    let query = asSelect().count()
    return try query.fetchOne(db) ?? 0
  }
}

extension SelectStatement where QueryValue == (), Joins == () {
  @inlinable
  public func fetchAll(_ db: Database) throws -> [From.QueryOutput] {
    try Array(fetchCursor(db))
  }

  @inlinable
  public func fetchOne(_ db: Database) throws -> From.QueryOutput? {
    try fetchCursor(db).next()
  }

  @inlinable
  public func fetchCursor(_ db: Database) throws -> QueryCursor<From.QueryOutput> {
    try QueryValueCursor<From>(db: db, query: query)
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SelectStatement where QueryValue == () {
  @inlinable
  public func fetchAll<each J: StructuredQueriesCore.Table>(
    _ db: Database
  ) throws -> [(From.QueryOutput, repeat (each J).QueryOutput)]
  where Joins == (repeat each J) {
    try Array(fetchCursor(db))
  }

  @inlinable
  public func fetchOne<each J: StructuredQueriesCore.Table>(
    _ db: Database
  ) throws -> (From.QueryOutput, repeat (each J).QueryOutput)?
  where Joins == (repeat each J) {
    try fetchCursor(db).next()
  }

  @inlinable
  public func fetchCursor<each J: StructuredQueriesCore.Table>(
    _ db: Database
  ) throws -> QueryCursor<(From.QueryOutput, repeat (each J).QueryOutput)>
  where Joins == (repeat each J) {
    try QueryPackCursor<From, repeat each J>(db: db, query: query)
  }
}
