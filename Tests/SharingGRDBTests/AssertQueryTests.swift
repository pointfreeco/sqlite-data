import Dependencies
import DependenciesTestSupport
import Foundation
import GRDB
import Sharing
import SharingGRDB
import SharingGRDBTestSupport
import SnapshotTesting
import StructuredQueries
import Testing

@Suite(
  .dependency(\.defaultDatabase, try .database()),
  .snapshots(record: .failed),
  .serialized
)
struct AssertQueryTests {
  @Dependency(\.defaultDatabase) var database
  @Test func assertQueryBasic() throws {
    try database.read { db in
      assertQuery(
        Record.all.select(\.id)
      ) {
        try $0.fetchAll(db)
      } results: {
        """
        ┌───┐
        │ 1 │
        │ 2 │
        │ 3 │
        └───┘
        """
      }
    }
  }
  @Test func assertQueryRecord() throws {
    try database.read { db in
      assertQuery(
        Record.where { $0.id == 1 }
      ) {
        try $0.fetchAll(db)
      } results: {
        """
        ┌────────────────────────────────────────┐
        │ Record(                                │
        │   id: 1,                               │
        │   date: Date(1970-01-01T00:00:42.000Z) │
        │ )                                      │
        └────────────────────────────────────────┘
        """
      }
    }
  }
  @Test func assertQueryBasicIncludeSQL() throws {
    try database.read { db in
      assertQuery(
        includeSQL: true,
        Record.all.select(\.id)
      ) {
        try $0.fetchAll(db)
      } sql: {
        """
        SELECT "records"."id"
        FROM "records"
        """
      } results: {
        """
        ┌───┐
        │ 1 │
        │ 2 │
        │ 3 │
        └───┘
        """
      }
    }
  }
  @Test func assertQueryRecordIncludeSQL() throws {
    try database.read { db in
      assertQuery(
        includeSQL: true,
        Record.where { $0.id == 1 }
      ) {
        try $0.fetchAll(db)
      } sql: {
        """
        SELECT "records"."id", "records"."date"
        FROM "records"
        WHERE ("records"."id" = 1)
        """
      } results: {
        """
        ┌────────────────────────────────────────┐
        │ Record(                                │
        │   id: 1,                               │
        │   date: Date(1970-01-01T00:00:42.000Z) │
        │ )                                      │
        └────────────────────────────────────────┘
        """
      }
    }
  }
}

@Table
private struct Record: Equatable {
  let id: Int
  @Column(as: Date.UnixTimeRepresentation.self)
  var date = Date(timeIntervalSince1970: 42)
}
extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "records" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "date" INTEGER NOT NULL DEFAULT 42
        )
        """
      )
      .execute(db)
      for _ in 1...3 {
        _ = try Record.insert { Record.Draft() }.execute(db)
      }
    }
    return database
  }
}
