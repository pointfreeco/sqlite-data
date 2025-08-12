import Foundation
import OSLog
import SharingGRDB
import Tagged

extension Tagged: @retroactive IdentifierStringConvertible where RawValue: IdentifierStringConvertible {
  public init?(rawIdentifier: String) {
    guard let rawValue = RawValue(rawIdentifier: rawIdentifier) else {
      return nil
    }
    self.init(rawValue: rawValue)
  }
}

@Table
struct Counter: Identifiable {
  
  typealias ID = Tagged<Self, UUID>
  
  let id: ID
  var count = 0
}

func appDatabase() throws -> any DatabaseWriter {
  @Dependency(\.context) var context
  let database: any DatabaseWriter
  var configuration = Configuration()
  configuration.prepareDatabase { db in
    try db.attachMetadatabase()
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
    let path = try makeDBURL().path()
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

func makeDBURL() throws -> URL {
  let fileManager = FileManager.default
  let containerURL = fileManager.containerURL(
    forSecurityApplicationGroupIdentifier: "group.indave.pointfree.cloudkitdemo"
  )
  let directoryURL = containerURL!.appendingPathComponent("Database", isDirectory: true)

  try fileManager.createDirectory(
    at: directoryURL,
    withIntermediateDirectories: true
  )

  let databaseURL = directoryURL.appendingPathComponent("db.sqlite")

  return databaseURL
}

private let logger = Logger(subsystem: "CloudKitDemo", category: "Database")
