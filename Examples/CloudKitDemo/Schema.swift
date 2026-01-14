import Foundation
import OSLog
import SQLiteData

@Table
nonisolated struct Counter: Identifiable {
  let id: UUID
  var count = 0
}

extension DependencyValues {
  mutating func bootstrapDatabase() throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      try db.attachMetadatabase()
    }
    let database = try SQLiteData.defaultDatabase(configuration: configuration)
    logger.debug(
      """
      App database
      open "\(database.path)"
      """
    )

    var migrator = DatabaseMigrator()
    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif
    migrator.registerMigration("Create tables") { db in
      try #sql(
        """
        CREATE TABLE "counters" (
          "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
          "count" INT NOT NULL ON CONFLICT REPLACE DEFAULT 0
        ) STRICT
        """
      )
      .execute(db)
    }
    try migrator.migrate(database)
    defaultDatabase = database
    defaultSyncEngine = try SyncEngine(
      for: defaultDatabase,
      tables: Counter.self
    )
  }
}

private let logger = Logger(subsystem: "CloudKitDemo", category: "Database")

#if DEBUG
  extension DatabaseWriter {
    func seedSampleData() throws {
      try write { db in
        try db.seed {
          Counter.Draft(count: 24)
          Counter.Draft(count: 1729)
        }
      }
    }
  }
#endif
