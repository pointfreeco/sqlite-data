import Foundation
import SharingGRDB

@Table
struct Counter: Identifiable {
  let id: UUID
  var count = 0
  var parentCounterID: Counter.ID?
  var name = ""
}

func appDatabase() throws -> any DatabaseWriter {
  let path = URL.documentsDirectory.appendingPathComponent("db.sqlite").path()
  var configuration = Configuration()
  configuration.foreignKeysEnabled = false
  configuration.prepareDatabase { db in
    db.trace {
      print($0.expandedDescription)
    }
  }
  let database = try DatabasePool(path: path, configuration: configuration)

  var migrator = DatabaseMigrator()
  #if DEBUG
  migrator.eraseDatabaseOnSchemaChange = true
  #endif
  migrator.registerMigration("Create tables") { db in
    try #sql("""
      CREATE TABLE "counters" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "count" INT NOT NULL DEFAULT 0,
        "parentCounterID" TEXT REFERENCES "counters"("id") ON DELETE CASCADE,
        "name" TEXT NOT NULL DEFAULT ''
      )
      """)
    .execute(db)
  }
  try migrator.migrate(database)

  return database
}
