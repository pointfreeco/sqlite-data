#if canImport(CloudKit)
  import Foundation

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  func defaultMetadatabase(
    logger: any SyncEngineLogger,
    url: URL
  ) throws -> any DatabaseWriter {
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

    let metadatabase: any DatabaseWriter =
      if url.isInMemory {
        try DatabaseQueue(path: url.absoluteString)
      } else {
        try DatabasePool(path: url.path(percentEncoded: false))
      }
    try migrate(metadatabase: metadatabase)
    return metadatabase
  }

  func migrate(metadatabase: some DatabaseWriter) throws {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create Metadata Tables") { db in
      try #sql(
        """
        CREATE TABLE "\(raw: .sqliteDataCloudKitSchemaName)_metadata" (
          "recordPrimaryKey" TEXT NOT NULL,
          "recordType" TEXT NOT NULL,
          "recordName" TEXT NOT NULL AS ("recordPrimaryKey" || ':' || "recordType"),
          "zoneName" TEXT NOT NULL,
          "ownerName" TEXT NOT NULL,
          "parentRecordPrimaryKey" TEXT,
          "parentRecordType" TEXT,
          "parentRecordName" TEXT AS ("parentRecordPrimaryKey" || ':' || "parentRecordType"),
          "lastKnownServerRecord" BLOB,
          "_lastKnownServerRecordAllFields" BLOB,
          "share" BLOB,
          "hasLastKnownServerRecord" INTEGER NOT NULL AS ("lastKnownServerRecord" IS NOT NULL),
          "isShared" INTEGER NOT NULL AS ("share" IS NOT NULL),
          "userModificationTime" INTEGER NOT NULL DEFAULT (\($currentTime())),
          "_isDeleted" INTEGER NOT NULL DEFAULT 0,

          PRIMARY KEY ("recordPrimaryKey", "recordType"),
          UNIQUE ("recordName")
        ) STRICT
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX "\(raw: .sqliteDataCloudKitSchemaName)_metadata_zoneID"
        ON "\(raw: .sqliteDataCloudKitSchemaName)_metadata"("ownerName", "zoneName")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX "\(raw: .sqliteDataCloudKitSchemaName)_metadata_parentRecordName"
        ON "\(raw: .sqliteDataCloudKitSchemaName)_metadata"("parentRecordName")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX "\(raw: .sqliteDataCloudKitSchemaName)_metadata_isShared"
        ON "\(raw: .sqliteDataCloudKitSchemaName)_metadata"("isShared")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE INDEX IF NOT EXISTS "\(raw: .sqliteDataCloudKitSchemaName)_metadata_hasLastKnownServerRecord"
        ON "\(raw: .sqliteDataCloudKitSchemaName)_metadata"("hasLastKnownServerRecord")
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "\(raw: .sqliteDataCloudKitSchemaName)_recordTypes" (
          "tableName" TEXT NOT NULL PRIMARY KEY,
          "schema" TEXT NOT NULL,
          "tableInfo" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "\(raw: .sqliteDataCloudKitSchemaName)_stateSerialization" (
          "scope" TEXT NOT NULL PRIMARY KEY,
          "data" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "\(raw: .sqliteDataCloudKitSchemaName)_unsyncedRecordIDs" (
          "recordName" TEXT NOT NULL,
          "zoneName" TEXT NOT NULL,
          "ownerName" TEXT NOT NULL,
          PRIMARY KEY ("recordName", "zoneName", "ownerName")
        ) STRICT
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "\(raw: .sqliteDataCloudKitSchemaName)_pendingRecordZoneChanges" (
          "pendingRecordZoneChange" BLOB NOT NULL
        ) STRICT
        """
      )
      .execute(db)
    }
    #if DEBUG
      try metadatabase.read { db in
        let hasSchemaChanges = try migrator.hasSchemaChanges(db)
        assert(
          !hasSchemaChanges,
          """
          A previously run migration has been removed or edited. \
          Metadatabase migrations must not be modified after release.
          """
        )
      }
    #endif
    try migrator.migrate(metadatabase)
  }
#endif
