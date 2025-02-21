import Foundation
import GRDB
import StructuredQueriesGRDB
import Testing

@Suite struct MigrationTests {
  @Test func dates() throws {
    let database = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create schema") { db in
      try db.create(table: "models") { t in
        t.column("date", .datetime).notNull()
      }
    }
    try migrator.migrate(database)

    let timestamp = 123.456
    try database.write { db in
      try db.execute(
        literal: "INSERT INTO models (date) VALUES (\(Date(timeIntervalSince1970: timestamp)))"
      )
    }
    try database.read { db in
      let grdbDate = try Date.fetchOne(db, sql: "SELECT * FROM models")
      try #expect(abs(#require(grdbDate).timeIntervalSince1970 - timestamp) < 0.001)

      let date = try #require(try Model.all().fetchOne(db)).date
      try #expect(abs(#require(date).timeIntervalSince1970 - timestamp) < 0.001)
    }
  }
}

@Table private struct Model {
  @Column(as: .iso8601)
  var date: Date
}
