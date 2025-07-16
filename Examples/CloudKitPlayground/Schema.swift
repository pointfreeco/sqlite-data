import Foundation
import SharingGRDB
import os

@Table struct ModelA: Identifiable {
  let id: UUID
  var count = 0
}
@Table struct ModelB: Identifiable {
  let id: UUID
  var isOn = false
  var modelAID: ModelA.ID
}
@Table struct ModelC: Identifiable {
  let id: UUID
  var title = ""
  var modelBID: ModelB.ID
}

func appDatabase() throws -> any DatabaseWriter {
  @Dependency(\.context) var context
  let database: any DatabaseWriter
  var configuration = Configuration()
  configuration.prepareDatabase { db in
    try db.attachMetadatabase(
      containerIdentifier: "iCloud.co.pointfree.SQLiteData.demos.CloudKitPlayground"
    )
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
  migrator.registerMigration("Create tables") { db in
    try #sql("""
      CREATE TABLE "modelAs" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "count" INTEGER NOT NULL
      )
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "modelBs" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "isOn" INTEGER NOT NULL,
        "modelAID" INTEGER NOT NULL REFERENCES "modelAs"("id") ON DELETE CASCADE
      )
      """)
    .execute(db)
    try #sql("""
      CREATE TABLE "modelCs" (
        "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
        "title" TEXT NOT NULL,
        "modelBID" INTEGER NOT NULL REFERENCES "modelBs"("id") ON DELETE CASCADE
      )
      """)
    .execute(db)
  }
  try migrator.migrate(database)

  return database
}

let logger = Logger(subsystem: "CloudKitPlayground", category: "Database")
