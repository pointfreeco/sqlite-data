import DependenciesTestSupport
import Foundation
import SQLiteData
import SQLiteDataTestSupport
import SnapshotTesting
import Testing

@Suite(.dependency(\.defaultDatabase, try .database()))
struct BulkTests {
  @Dependency(\.defaultDatabase) var database

  @Test func bulk() throws {
    try database.write { db in
      try db.bulkInsert([
        Record(id: 1, title: "Blob")
      ])

      let records = try Record.all.fetchAll(db)
      #expect(records == [Record(id: 1, title: "Blob")])
    }
  }
}



@Table private struct Record: Equatable {
  let id: Int
  var title = ""
}
extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "records" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "title" TEXT NOT NULL
        )
        """
      )
      .execute(db)
    }
    return database
  }
}
