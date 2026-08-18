import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@Suite(.dependency(\.defaultDatabase, try .database()))
struct StatementCacheTests {
  @Dependency(\.defaultDatabase) var database

  @Test func `rebinding across cached statement reuse`() throws {
    try database.read { db in
      for id in 1...10 {
        let record = try Record.where { $0.id.eq(id) }.fetchOne(db)
        #expect(record?.id == id)
        #expect(record?.value == "value \(id)")
      }
    }
  }

  @Test func `escaping cursor does not share cached statement`() throws {
    try database.read { db in
      let query = Record.where { $0.id.lte(3) }
      let cursor = try query.fetchCursor(db)
      #expect(try cursor.next()?.id == 1)
      #expect(try query.fetchAll(db).map(\.id) == [1, 2, 3])
      #expect(try cursor.next()?.id == 2)
      #expect(try cursor.next()?.id == 3)
      #expect(try cursor.next() == nil)
    }
  }

  @Test func `cached execute reuse`() throws {
    try database.write { db in
      for id in 11...20 {
        try Record.insert { Record(id: id, value: "value \(id)") }.execute(db)
      }
      #expect(try Record.all.fetchCount(db) == 20)
    }
  }

  @Test func `schema change between cached uses`() throws {
    try database.write { db in
      #expect(try Record.all.fetchCount(db) == 10)
      try #sql(#"ALTER TABLE "records" ADD COLUMN "extra" TEXT"#).execute(db)
      #expect(try Record.all.fetchCount(db) == 10)
      #expect(try Record.where { $0.id.eq(5) }.fetchOne(db)?.value == "value 5")
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
          "id" INTEGER PRIMARY KEY,
          "value" TEXT NOT NULL
        )
        """
      )
      .execute(db)
      for id in 1...10 {
        try Record.insert { Record(id: id, value: "value \(id)") }.execute(db)
      }
    }
    return database
  }
}
