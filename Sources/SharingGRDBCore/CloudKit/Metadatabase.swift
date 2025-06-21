import Foundation
import os

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
func defaultMetadatabase(
  logger: Logger,
  url: URL
) throws -> any DatabaseReader {
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
    try SQLQueryExpression(
      """
      CREATE TABLE IF NOT EXISTS "\(raw: .sqliteDataCloudKitSchemaName)_metadata" (
        "recordType" TEXT NOT NULL,
        "recordName" TEXT NOT NULL PRIMARY KEY,
        "parentRecordName" TEXT,
        "lastKnownServerRecord" BLOB,
        "share" BLOB,
        "userModificationDate" TEXT
      ) STRICT
      """
    )
    .execute(db)
    // TODO: Should we add an index to recordType?
    // TODO: Do we ever query for "parentRecordName"? should we add an index?
    try SQLQueryExpression(
      """
      CREATE INDEX IF NOT EXISTS "\(raw: .sqliteDataCloudKitSchemaName)_metadata_share"
      ON "\(raw: .sqliteDataCloudKitSchemaName)_metadata"("share") WHERE "share" IS NOT NULL
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
