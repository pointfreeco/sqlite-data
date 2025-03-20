import GRDB
import Foundation
import IssueReporting
import SQLite3
@_exported import StructuredQueriesCore

extension StructuredQueriesCore.Statement {
  public func execute(_ db: GRDB.Database) throws
  where QueryValue == () {
    guard let handle = db.sqliteConnection else {
      reportIssue("Can't fetch from closed database connection")
      return
    }
    try Database(handle, db: db).execute(self)
  }

  public func fetchAll<each Value: QueryRepresentable>(
    _ db: GRDB.Database
  ) throws -> [(repeat (each Value).QueryOutput)]
  where QueryValue == (repeat each Value) {
    guard let handle = db.sqliteConnection else {
      reportIssue("Can't fetch from closed database connection")
      return []
    }
    return try Database(handle, db: db).execute(self)
  }

  public func fetchAll(
    _ db: GRDB.Database
  ) throws -> [QueryValue.QueryOutput]
  where QueryValue: QueryRepresentable {
    guard let handle = db.sqliteConnection else {
      reportIssue("Can't fetch from closed database connection")
      return []
    }
    return try Database(handle, db: db).execute(self)
  }

  public func fetchOne<each Value: QueryRepresentable>(
    _ db: GRDB.Database
  ) throws -> (repeat (each Value).QueryOutput)?
  where QueryValue == (repeat each Value) {
    guard let handle = db.sqliteConnection else {
      reportIssue("Can't fetch from closed database connection")
      return nil
    }
    return try Database(handle, db: db).execute(self).first
  }

  public func fetchOne(
    _ db: GRDB.Database
  ) throws -> QueryValue.QueryOutput?
  where QueryValue: QueryRepresentable {
    guard let handle = db.sqliteConnection else {
      reportIssue("Can't fetch from closed database connection")
      return nil
    }
    return try Database(handle, db: db).execute(self).first
  }
}

extension SelectStatement where QueryValue == () {
  public func fetchAll<each J: StructuredQueriesCore.Table>(
    _ db: GRDB.Database
  ) throws -> [(From.QueryOutput, repeat (each J).QueryOutput)]
  where Joins == (repeat each J) {
    try self.selectStar().fetchAll(db)
  }

  public func fetchOne<each J: StructuredQueriesCore.Table>(
    _ db: GRDB.Database
  ) throws -> (From.QueryOutput, repeat (each J).QueryOutput)?
  where Joins == (repeat each J) {
    try self.selectStar().fetchOne(db)
  }
}
