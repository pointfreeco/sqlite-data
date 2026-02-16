import DependenciesTestSupport
import Foundation
import SQLiteData
import SQLiteDataTestSupport
import Testing

@Suite(.dependency(\.defaultDatabase, try .database()))
struct DateTests {
  @Dependency(\.defaultDatabase) var database

  @Test func roundtrip() throws {
    let date = Date(timeIntervalSinceReferenceDate: 793109282.061)
    let insertedRecord = try database.write { db in
      try Record.insert { Record.Draft(date: date) }
      .returning(\.self)
      .fetchOne(db)!
    }
    let updatedRecord = try database.write { db in
      try Record
        .update(insertedRecord)
      .returning(\.self)
      .fetchOne(db)!
    }
    #expect(insertedRecord.date == date)
    #expect(insertedRecord.date == updatedRecord.date)
  }
}

@Table
private struct Record: Equatable {
  let id: Int
  var date: Date
}

extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "records" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "date" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
    }
    return database
  }
}
