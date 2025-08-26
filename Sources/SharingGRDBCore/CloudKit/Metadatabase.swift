#if canImport(CloudKit)
import Foundation
import os

#if SharingGRDBSwiftLog
  import Logging
#endif

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

  @Dependency(\.context) var context
  guard !url.isInMemory || context != .live
  else {
    struct InMemoryDatabase: Error {}
    throw InMemoryDatabase()
  }

  let metadatabase: any DatabaseWriter = if url.isInMemory {
    try DatabaseQueue(
      path: url.absoluteString,
      configuration: configuration
    )
  } else {
    try DatabasePool(
      path: url.path(percentEncoded: false),
      configuration: configuration
    )
  }
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
        "recordPrimaryKey" TEXT NOT NULL,
        "recordType" TEXT NOT NULL,
        "recordName" TEXT NOT NULL AS ("recordPrimaryKey" || ':' || "recordType"),
        "parentRecordPrimaryKey" TEXT,
        "parentRecordType" TEXT,
        "parentRecordName" TEXT AS ("parentRecordPrimaryKey" || ':' || "parentRecordType"),
        "lastKnownServerRecord" BLOB,
        "_lastKnownServerRecordAllFields" BLOB,
        "share" BLOB,
        "isShared" INTEGER NOT NULL AS ("share" IS NOT NULL),
        "userModificationDate" TEXT NOT NULL DEFAULT (\(.datetime())),
        "_isDeleted" INTEGER NOT NULL DEFAULT 0,

        PRIMARY KEY ("recordPrimaryKey", "recordType"),
        UNIQUE ("recordName")
      ) STRICT
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE INDEX IF NOT EXISTS "\(raw: .sqliteDataCloudKitSchemaName)_metadata_parentRecordName"
      ON "\(raw: .sqliteDataCloudKitSchemaName)_metadata"("parentRecordName")
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE INDEX IF NOT EXISTS "\(raw: .sqliteDataCloudKitSchemaName)_metadata_isShared"
      ON "\(raw: .sqliteDataCloudKitSchemaName)_metadata"("isShared")
      """
    )
    .execute(db)
    try SQLQueryExpression(
      """
      CREATE TABLE IF NOT EXISTS "\(raw: .sqliteDataCloudKitSchemaName)_recordTypes" (
        "tableName" TEXT NOT NULL PRIMARY KEY,
        "schema" TEXT NOT NULL,
        "tableInfo" TEXT NOT NULL
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
    try SQLQueryExpression(
      """
      CREATE TABLE IF NOT EXISTS "\(raw: .sqliteDataCloudKitSchemaName)_unsyncedRecordIDs" (
        "recordName" TEXT NOT NULL,
        "zoneName" TEXT NOT NULL,
        "ownerName" TEXT NOT NULL,
        PRIMARY KEY ("recordName", "zoneName", "ownerName")
      ) STRICT
      """
    )
    .execute(db)
  }
  try migrator.migrate(metadatabase)
  return metadatabase
}

extension QueryFragment {
  static func datetime() -> Self {
    Self("\(raw: .sqliteDataCloudKitSchemaName)_datetime()")
  }
}
#endif
