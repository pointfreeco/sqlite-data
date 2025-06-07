import Foundation
import os

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
func defaultMetadatabase(
  logger: Logger,
  url: URL
) throws -> any DatabaseWriter {
  var configuration = Configuration()
  configuration.prepareDatabase { [logger] db in
    db.trace {
      logger.trace("\($0.expandedDescription)")
    }
  }
  logger.debug(
    """
    Metadatabase connection:
    open "\(url.path(percentEncoded: false))"
    """
  )
  try FileManager.default.createDirectory(
    at: .applicationSupportDirectory,
    withIntermediateDirectories: true
  )
  let metadatabase = try DatabasePool(
    path: url.path(percentEncoded: false),
    configuration: configuration
  )
  // TODO: go towards idempotent migrations instead of GRDB migrator by the end of all of this
  var migrator = DatabaseMigrator()
  // TODO: do we want this?
  #if DEBUG
    migrator.eraseDatabaseOnSchemaChange = true
  #endif
  migrator.registerMigration("Create Metadata Tables") { db in
    // TODO: Should "recordName" be "collate no case"?
    // TODO: should primary key be (recordType, recordName) so that we can use autoincrementing
    //       UUIDs in tests?
    try SQLQueryExpression(
      """
      CREATE TABLE IF NOT EXISTS "\(raw: .sqliteDataCloudKitSchemaName)_metadata" (
        "recordType" TEXT NOT NULL,
        "recordName" TEXT NOT NULL PRIMARY KEY,
        "zoneName" TEXT NOT NULL,
        "ownerName" TEXT NOT NULL,
        "parentRecordName" TEXT,
        "lastKnownServerRecord" BLOB,
        "share" BLOB,
        "userModificationDate" TEXT
      ) STRICT
      """
    )
    .execute(db)
    // TODO: Should we have "parentRecordName TEXT REFERENCES metadata(recordName) ON DELETE CASCADE" ?
    // TODO: Do we ever query for "parentRecordName"? should we add an index?
    try SQLQueryExpression(
      """
      CREATE INDEX IF NOT EXISTS "\(raw: .sqliteDataCloudKitSchemaName)_metadata_zoneName_ownerName"
      ON "\(raw: .sqliteDataCloudKitSchemaName)_metadata" ("zoneName", "ownerName")
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE TABLE IF NOT EXISTS "\(raw: .sqliteDataCloudKitSchemaName)_recordTypes" (
        "tableName" TEXT NOT NULL PRIMARY KEY,
        "schema" TEXT NOT NULL
      ) STRICT
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE TABLE IF NOT EXISTS "\(raw: .sqliteDataCloudKitSchemaName)_stateSerialization" (
        "scope" TEXT NOT NULL PRIMARY KEY,
        "data" TEXT NOT NULL
      ) STRICT
      """
    )
    .execute(db)
  }
  try migrator.migrate(metadatabase)
  return metadatabase
}
