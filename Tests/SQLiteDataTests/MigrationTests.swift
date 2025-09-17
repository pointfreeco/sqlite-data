import Foundation
import SQLiteData
import Testing

@Suite struct MigrationTests {
  @available(iOS 15, *)
  @Test func dates() throws {
    let database = try DatabaseQueue()
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "models" (
          "date" TEXT NOT NULL
        )
        """
      )
      .execute(db)
    }

    let timestamp = 123.456
    try database.write { db in
      try db.execute(
        literal: "INSERT INTO models (date) VALUES (\(Date(timeIntervalSince1970: timestamp)))"
      )
    }
    try database.read { db in
      let grdbDate = try Date.fetchOne(db, sql: "SELECT * FROM models")
      try #expect(abs(#require(grdbDate).timeIntervalSince1970 - timestamp) < 0.001)

      let date = try #require(try Model.all.fetchOne(db)).date
      #expect(abs(date.timeIntervalSince1970 - timestamp) < 0.001)
    }
  }
}

@available(iOS 15, *)
@Table private struct Model {
  var date: Date
}
