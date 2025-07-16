import Foundation
import OSLog
import SharingGRDB

@Table
struct Counter: Identifiable {
  let id: UUID
  var count = 0
}

func appDatabase() throws -> any DatabaseWriter {
  @Dependency(\.context) var context
  let database: any DatabaseWriter
  var configuration = Configuration()
  configuration.prepareDatabase { db in
    try db.attachMetadatabase(containerIdentifier: "iCloud.co.pointfree.SQLiteData.demos.CloudKitDemo")
    #if DEBUG
      db.trace(options: .profile) {
        if context == .live {
          logger.debug("\($0.expandedDescription)")
        } else {
          print("\($0.expandedDescription)")
        }
      }
    #endif
  }
  if context == .preview {
    database = try DatabaseQueue(configuration: configuration)
  } else {
    let path =
      context == .live
      ? URL.documentsDirectory.appending(component: "db.sqlite").path()
      : URL.temporaryDirectory.appending(component: "\(UUID().uuidString)-db.sqlite").path()
    logger.debug(
      """
      App database
      open "\(path)"
      """
    )
    database = try DatabasePool(path: path, configuration: configuration)
  }

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

private let logger = Logger(subsystem: "CloudKitDemo", category: "Database")
