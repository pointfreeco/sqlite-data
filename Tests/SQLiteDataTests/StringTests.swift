import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@Suite(.dependency(\.defaultDatabase, try .database()))
struct NulStringTests {
  @Dependency(\.defaultDatabase) var database

  @Test func `decode string with NUL characters`() throws {
    try database.read { db in
      let value = try #sql("SELECT 'a' || char(0) || 'b'", as: String.self).fetchOne(db)
      #expect(value == stringWithNul)
    }
  }

  // We currently cannot insert strings with NUL characters until
  // https://github.com/groue/GRDB.swift/pull/1880 is merged.
  @Test func `bind and fetch NUL strings`() throws {
    withKnownIssue("Binding strings with NUL's doesn't work") {
      try database.read { db in
        let back = try #sql("SELECT \(bind: stringWithNul)", as: String.self).fetchOne(db)
        #expect(back == stringWithNul)
      }
    }
    withKnownIssue("Inserting strings with NUL's doesn't work") {
      let insertedRecord = try #require(
        try database.write { db in
          try Record.insert { Record.Draft(value: stringWithNul) }
            .returning(\.self)
            .fetchOne(db)
        }
      )
      #expect(insertedRecord.value == stringWithNul)
    }
  }
}

@Table
private struct Record: Equatable {
  let id: Int
  var value: String
}

extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "records" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "value" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
    }
    return database
  }
}

private let stringWithNul = "a\u{0}b"
