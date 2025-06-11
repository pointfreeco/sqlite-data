import Foundation
import SharingGRDB

@Table
struct Counter: Identifiable {
  let id: UUID
  var count = 0

  static let withShare = Counter
    .join(Metadata.all) {
      #sql("\($0.id) = \($1.recordName)")
      && $1.share.isNot(nil)
    }

  static let nonShared = Counter
    .where { counter in
      !counter.id.in(
        #sql("\(Metadata.where { $0.share.isNot(nil) }.select(\.recordName))")
      )
    }
}

func appDatabase() throws -> any DatabaseWriter {
  let path = URL.documentsDirectory.appendingPathComponent("db.sqlite").path()
  var configuration = Configuration()
  configuration.foreignKeysEnabled = false
  configuration.prepareDatabase { db in
    db.trace {
      print($0.expandedDescription)
    }
    try db.attachMetadatabase(containerIdentifier: "iCloud.co.pointfree.SharingGRDB.CloudKitDemo")
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
        "count" INT NOT NULL DEFAULT 0
      )
      """)
    .execute(db)
  }
  try migrator.migrate(database)

  return database
}
