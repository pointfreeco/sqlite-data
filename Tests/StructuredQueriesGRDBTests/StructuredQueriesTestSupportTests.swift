import GRDB
import SnapshotTesting
import StructuredQueriesGRDB
import StructuredQueriesTestSupport
import Testing

@Suite
struct StructuredQueriesTestSupportGRDBTests {
  let database: DatabaseQueue
  init() throws {
    var configuration = Configuration()
    configuration.prepareDatabase {
      $0.trace { print($0) }
    }
    database = try DatabaseQueue(configuration: configuration)
    try database.write { db in
      try #sql(#"CREATE TABLE "numbers" ("value" INTEGER NOT NULL)"#)
        .execute(db)
    }
    try database.write { db in
      try db.seed {
        Number(value: 1)
        Number(value: 2)
        Number(value: 3)
      }
    }
  }
  @Test func assertQueryWorks() throws {
    try database.read { db in
      assertQuery(
        Number.all.select(\.value)
      ) {
        try $0.fetchAll(db)
      } sql: {
        """
        SELECT "numbers"."value"
        FROM "numbers"
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
  @Test func assertQueryAsyncWorks() async throws {
    try await database.read { db in
      assertQuery(
        Number.all.select(\.value)
      ) {
        try $0.fetchAll(db)
      } sql: {
        """
        SELECT "numbers"."value"
        FROM "numbers"
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
  @Test func assertQueryAsyncDetectsFailure() async throws {
    await withKnownIssue(
      """
      Before GRDB's async read/write methods respected TaskLocal,
      failing test were not detected. This test ensures that
      failing tests always fail.
      """
    ) {
      try await database.read { db in
        assertQuery(
          Number.all.select(\.value)
        ) {
          try $0.fetchAll(db)
        } sql: {
          """
          SELECT "numbers"."value"
          FROM "numbers"
          """
        } results: {
          """
          ┌───┐
          │ 1 │
          │ 2 │
          └───┘
          """
        }
      }
    }
  }
}

@Table private struct Number {
  var value = 0
}
