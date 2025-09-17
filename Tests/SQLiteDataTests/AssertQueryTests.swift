import DependenciesTestSupport
import Foundation
import SQLiteData
import SQLiteDataTestSupport
import SnapshotTesting
import Testing

@Suite(
  .dependency(\.defaultDatabase, try .database()),
  .snapshots(record: .missing),
)
struct AssertQueryTests {
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryBasic() throws {
    assertQuery(
      Record.all.select(\.id)
    ) {
      """
      ┌───┐
      │ 1 │
      │ 2 │
      │ 3 │
      └───┘
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryRecord() throws {
    assertQuery(
      Record.where { $0.id == 1 }
    ) {
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

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryBasicUpdate() throws {
    assertQuery(
      Record.all
        .update { $0.date = Date(timeIntervalSince1970: 45) }
        .returning { ($0.id, $0.date) }
    ) {
      """
      ┌───┬────────────────────────────────┐
      │ 1 │ Date(1970-01-01T00:00:45.000Z) │
      │ 2 │ Date(1970-01-01T00:00:45.000Z) │
      │ 3 │ Date(1970-01-01T00:00:45.000Z) │
      └───┴────────────────────────────────┘
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryRecordUpdate() throws {
    assertQuery(
      Record
        .where { $0.id == 1 }
        .update { $0.date = Date(timeIntervalSince1970: 45) }
        .returning(\.self)
    ) {
      """
      ┌────────────────────────────────────────┐
      │ Record(                                │
      │   id: 1,                               │
      │   date: Date(1970-01-01T00:00:45.000Z) │
      │ )                                      │
      └────────────────────────────────────────┘
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func assertQueryEmpty() throws {
    assertQuery(
      Record.all.where { $0.id == -1 }.select(\.id)
    ) {
      """
      (No results)
      """
    }
  }

  @Test(.snapshots(record: .never))
  func assertQueryFailsNoResultsNonEmptySnapshot() {
    withKnownIssue {
      assertQuery(
        Record.all.where { _ in false }
      ) {
        """
        XYZ
        """
      }
    }
  }

  #if DEBUG
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func assertQueryBasicIncludeSQL() throws {
      assertQuery(
        includeSQL: true,
        Record.all.select(\.id)
      ) {
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
  #endif

  #if DEBUG
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func assertQueryRecordIncludeSQL() throws {
      assertQuery(
        includeSQL: true,
        Record.where { $0.id == 1 }
      ) {
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
  #endif
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
