import CloudKit
import ConcurrencyExtras
import OSLog

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
public final actor SyncEngine {
  public static nonisolated let defaultZone = CKRecordZone(
    zoneName: "co.pointfree.SQLiteData.defaultZone"
  )

  let database: any DatabaseWriter
  let logger: Logger
  lazy var metadatabase: any DatabaseWriter = try! DatabaseQueue()
  private let metadatabaseURL: URL
  let tables: [any StructuredQueriesCore.PrimaryKeyedTable.Type]
  let tablesByName: [String: any StructuredQueriesCore.PrimaryKeyedTable.Type]
  let foreignKeysByTableName: [String: [ForeignKey]]
  var privateSyncEngine: (any SyncEngineProtocol)!
  var sharedSyncEngine: (any SyncEngineProtocol)!
  let defaultSyncEngines:
    (any DatabaseReader, SyncEngine)
      -> (private: any SyncEngineProtocol, shared: any SyncEngineProtocol)
  let _container: any Sendable

  public init(
    container: CKContainer,
    database: any DatabaseWriter,
    logger: Logger = Logger(subsystem: "SQLiteData", category: "CloudKit"),
    tables: [any PrimaryKeyedTable.Type]
  ) throws {
    try self.init(
      container: container,
      defaultSyncEngines: { database, syncEngine in
        (
          private: CKSyncEngine(
            CKSyncEngine.Configuration(
              database: container.privateCloudDatabase,
              stateSerialization: try? database.read { db in  // TODO: write test for this
                try StateSerialization.find(.private).select(\.data).fetchOne(db)
              },
              delegate: syncEngine
            )
          ),
          shared: CKSyncEngine(
            CKSyncEngine.Configuration(
              database: container.sharedCloudDatabase,
              stateSerialization: try? database.read { db in  // TODO: write test for this
                try StateSerialization.find(.shared).select(\.data).fetchOne(db)
              },
              delegate: syncEngine
            )
          )
        )
      },
      database: database,
      logger: logger,
      metadatabaseURL: URL.metadatabase(container: container),
      tables: tables
    )
  }

  package init(
    privateSyncEngine: any SyncEngineProtocol,
    sharedSyncEngine: any SyncEngineProtocol,
    database: any DatabaseWriter,
    metadatabaseURL: URL,
    tables: [any StructuredQueriesCore.PrimaryKeyedTable.Type]
  ) throws {
    try self.init(
      defaultSyncEngines: { _, _ in (privateSyncEngine, sharedSyncEngine) },
      database: database,
      logger: Logger(.disabled),
      metadatabaseURL: metadatabaseURL,
      tables: tables
    )
  }

  private init(
    container: (any Sendable)? = Void?.none,
    defaultSyncEngines: @escaping (
      any DatabaseReader,
      SyncEngine
    ) -> (private: any SyncEngineProtocol, shared: any SyncEngineProtocol),
    database: any DatabaseWriter,
    logger: Logger,
    metadatabaseURL: URL,
    tables: [any StructuredQueriesCore.PrimaryKeyedTable.Type]
  ) throws {
    // TODO: Explain why / link to documentation?
    precondition(
      !database.configuration.foreignKeysEnabled,
      """
      Foreign key support must be disabled to synchronize with CloudKit.
      """
    )
    self._container = container
    self.defaultSyncEngines = defaultSyncEngines
    self.database = database
    self.logger = logger
    self.metadatabaseURL = metadatabaseURL
    self.tables = tables
    self.tablesByName = Dictionary(uniqueKeysWithValues: tables.map { ($0.tableName, $0) })
    self.foreignKeysByTableName = Dictionary(
      uniqueKeysWithValues: try database.read { db in
        try tables.map { table -> (String, [ForeignKey]) in
          (
            table.tableName,
            try ForeignKey.all(table).fetchAll(db)
          )
        }
      }
    )
    Task {
      await withErrorReporting(.sqliteDataCloudKitFailure) {
        try await setUpSyncEngine()
      }
    }
  }

  nonisolated var container: CKContainer {
    _container as! CKContainer
  }

  package func setUpSyncEngine() throws {
    defer {
      (privateSyncEngine, sharedSyncEngine) = defaultSyncEngines(metadatabase, self)
    }

    metadatabase = try defaultMetadatabase
    // TODO: go towards idempotent migrations instead of GRDB migrator by the end of all of this
    var migrator = DatabaseMigrator()
    // TODO: do we want this?
    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif
    migrator.registerMigration("Create Metadata Tables") { db in
      // TODO: Should "recordName" be "collate no case"?
      try SQLQueryExpression(
        """
        CREATE TABLE IF NOT EXISTS "\(raw: .sqliteDataCloudKitSchemaName)_metadata" (
          "recordType" TEXT NOT NULL,
          "recordName" TEXT NOT NULL PRIMARY KEY,
          "zoneName" TEXT NOT NULL,
          "ownerName" TEXT NOT NULL,
          "parentRecordName" TEXT,
          "lastKnownServerRecord" BLOB,
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
    let previousRecordTypes = try metadatabase.read { db in
      try RecordType.all.fetchAll(db)
    }
    let currentRecordTypes = try database.read { db in
      try SQLQueryExpression(
        """
        SELECT "name", "sql" 
        FROM "sqlite_master" 
        WHERE "type" = 'table'
        AND "name" IN (\(tablesByName.keys.map(\.queryFragment).joined(separator: ", ")))
        """,
        as: RecordType.self
      )
      .fetchAll(db)
    }
    let recordTypesToFetch = currentRecordTypes.filter { currentRecordType in
      guard
        let existingRecordType = previousRecordTypes.first(where: { previousRecordType in
          currentRecordType.tableName == previousRecordType.tableName
        })
      else { return true }
      return existingRecordType.schema != currentRecordType.schema
    }
    if !recordTypesToFetch.isEmpty {
      // TODO: Should we avoid this unstructured task by making 'setUpSyncEngine' async?
      Task {
        await withErrorReporting(.sqliteDataCloudKitFailure) {
          try await metadatabase.write { db in
            for recordType in recordTypesToFetch {
              try RecordType.upsert(RecordType.Draft(recordType)).execute(db)
            }
          }
        }
        await withErrorReporting(.sqliteDataCloudKitFailure) {
          try await fetchChanges()
        }
      }
    }
    try database.write { db in
      try SQLQueryExpression(
        "ATTACH DATABASE \(metadatabaseURL) AS \(quote: .sqliteDataCloudKitSchemaName)"
      )
      .execute(db)
      db.add(function: .isUpdatingWithServerRecord)
      db.add(function: .getZoneName)
      db.add(function: .getOwnerName)
      db.add(function: .didUpdate(syncEngine: self))
      db.add(function: .willDelete(syncEngine: self))

      try Metadata.createTriggers(tables: tables, db: db)

      for table in tables {
        func open<T: PrimaryKeyedTable>(_: T.Type) throws {
          try createTriggers(table: table, db: db)
        }
        try open(table)
      }
    }
  }

  package func tearDownSyncEngine() throws {
    try database.write { db in
      for table in tables {
        func open<T: PrimaryKeyedTable>(_: T.Type) throws {
          try dropTriggers(table: table, db: db)
        }
        try open(table)
      }
      try Metadata.dropTriggers(db: db)
      db.remove(function: .willDelete(syncEngine: self))
      db.remove(function: .didUpdate(syncEngine: self))
      db.remove(function: .getOwnerName)
      db.remove(function: .getZoneName)
      db.remove(function: .isUpdatingWithServerRecord)
    }
    try database.writeWithoutTransaction { db in
      try SQLQueryExpression(
        "DETACH DATABASE \(quote: .sqliteDataCloudKitSchemaName)"
      )
      .execute(db)
    }
    try metadatabase.close()
    try FileManager.default.removeItem(at: metadatabaseURL)
  }

  // TODO: resendAll() ?

  public func fetchChanges() async throws {
    try await privateSyncEngine.fetchChanges()
    try await sharedSyncEngine.fetchChanges()
  }

  public func deleteLocalData() throws {
    try tearDownSyncEngine()
    withErrorReporting(.sqliteDataCloudKitFailure) {
      try database.write { db in
        for table in tables {
          func open<T: PrimaryKeyedTable>(_: T.Type) {
            withErrorReporting(.sqliteDataCloudKitFailure) {
              try T.delete().execute(db)
            }
          }
          open(table)
        }
      }
    }
    try setUpSyncEngine()
  }

  func didUpdate(recordName: String, zoneName: String, ownerName: String) {
    let syncEngine =
      ownerName == Self.defaultZone.zoneID.ownerName
      ? privateSyncEngine
      : sharedSyncEngine
    syncEngine?.state.add(
      pendingRecordZoneChanges: [
        .saveRecord(
          CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.ID(
              zoneName: zoneName,
              ownerName: ownerName
            )
          )
        )
      ]
    )
  }

  func willDelete(recordName: String, zoneName: String, ownerName: String) {
    let syncEngine =
      ownerName == Self.defaultZone.zoneID.ownerName
      ? privateSyncEngine
      : sharedSyncEngine
    syncEngine?.state.add(
      pendingRecordZoneChanges: [
        .deleteRecord(
          CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone.ID(
              zoneName: zoneName,
              ownerName: ownerName
            )
          )
        )
      ]
    )
  }

  private var defaultMetadatabase: any DatabaseWriter {
    get throws {
      var configuration = Configuration()
      configuration.prepareDatabase { [logger] db in
        db.trace {
          logger.trace("\($0.expandedDescription)")
        }
      }
      logger.debug(
        """
        Metadatabase connection:
        open "\(self.metadatabaseURL.path(percentEncoded: false))"
        """
      )
      try FileManager.default.createDirectory(
        at: .applicationSupportDirectory,
        withIntermediateDirectories: true
      )
      return try DatabaseQueue(
        path: metadatabaseURL.path(percentEncoded: false),
        configuration: configuration
      )
    }
  }

  private func createTriggers<T: PrimaryKeyedTable>(table: T.Type, db: Database) throws {
    let foreignKey =
      foreignKeysByTableName[T.tableName]?.count(where: \.notnull) == 1
      ? foreignKeysByTableName[T.tableName]?.first(where: \.notnull)
      : nil

    try Metadata.createTriggers(for: T.self, parentForeignKey: foreignKey, db: db)

    let foreignKeys = foreignKeysByTableName[T.tableName] ?? []
    for foreignKey in foreignKeys {
      try foreignKey.createTriggers(for: T.self, db: db)
    }
  }

  private func dropTriggers<T: PrimaryKeyedTable>(table: T.Type, db: Database) throws {
    let foreignKeys = foreignKeysByTableName[T.tableName] ?? []
    for foreignKey in foreignKeys {
      try foreignKey.dropTriggers(for: T.self, db: db)
    }
    try Metadata.dropTriggers(for: T.self, db: db)
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngine: CKSyncEngineDelegate {
  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    logger.log(event, syncEngine: syncEngine)

    switch event {
    case .accountChange(let event):
      handleAccountChange(event)
    case .stateUpdate(let event):
      handleStateUpdate(event, syncEngine: syncEngine)
    case .fetchedDatabaseChanges(let event):
      handleFetchedDatabaseChanges(event)
    case .sentDatabaseChanges:
      break
    case .fetchedRecordZoneChanges(let event):
      handleFetchedRecordZoneChanges(
        modifications: event.modifications.map(\.record),
        deletions: event.deletions.map { ($0.recordID, $0.recordType) }
      )
    case .sentRecordZoneChanges(let event):
      handleSentRecordZoneChanges(event, syncEngine: syncEngine)
    case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .willFetchChanges,
      .didFetchChanges, .willSendChanges, .didSendChanges:
      break
    @unknown default:
      break
    }
  }

  public func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    let allChanges = syncEngine.state.pendingRecordZoneChanges.filter(
      context.options.scope.contains
    )
    guard !allChanges.isEmpty
    else { return nil }

    var allChangesByIsDeleted = Dictionary(grouping: allChanges) {
      switch $0 {
      case .deleteRecord: true
      case .saveRecord: false
      @unknown default: false
      }
    }
    allChangesByIsDeleted[true]?.reverse()
    let changes = allChangesByIsDeleted.reduce(into: []) { changes, keyValue in
      changes += keyValue.value
    }

    #if DEBUG
      struct State {
        var missingTables: [CKRecord.ID] = []
        var missingRecords: [CKRecord.ID] = []
        var sentRecords: [CKRecord.ID] = []
      }
      let state = LockIsolated(State())
      defer {
        let state = state.withValue(\.self)
        let missingTables = Dictionary(grouping: state.missingTables, by: \.zoneID.zoneName)
          .reduce(into: [String]()) {
            strings,
            keyValue in strings += ["\(keyValue.key) (\(keyValue.value.count))"]
          }
          .joined(separator: ", ")
        let missingRecords = Dictionary(grouping: state.missingRecords, by: \.zoneID.zoneName)
          .reduce(into: [String]()) {
            strings,
            keyValue in strings += ["\(keyValue.key) (\(keyValue.value.count))"]
          }
          .joined(separator: ", ")
        let sentRecords = Dictionary(grouping: state.sentRecords, by: \.zoneID.zoneName)
          .reduce(into: [String]()) {
            strings,
            keyValue in strings += ["\(keyValue.key) (\(keyValue.value.count))"]
          }
          .joined(separator: ", ")
        logger.debug(
          """
          [\(syncEngine.scope.label)] nextRecordZoneChangeBatch: \(context.reason)
            \(state.missingTables.isEmpty ? "⚪️ No missing tables" : "⚠️ Missing tables: \(missingTables)")
            \(state.missingRecords.isEmpty ? "⚪️ No missing records" : "⚠️ Missing records: \(missingRecords)")
            \(state.sentRecords.isEmpty ? "⚪️ No sent records" : "✅ Sent records: \(sentRecords)")
          """
        )
      }
    #endif

    let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
      #if DEBUG
        var missingTable: CKRecord.ID?
        var missingRecord: CKRecord.ID?
        var sentRecord: CKRecord.ID?
        defer {
          state.withValue { [missingTable, missingRecord, sentRecord] in
            if let missingTable { $0.missingTables.append(missingTable) }
            if let missingRecord { $0.missingRecords.append(missingRecord) }
            if let sentRecord { $0.sentRecords.append(sentRecord) }
          }
        }
      #endif

      guard let metadata = await metadataFor(recordID: recordID)
      else {
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        return nil
      }
      guard let table = tablesByName[metadata.recordType]
      else {
        reportIssue("")
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        missingTable = recordID
        return nil
      }
      func open<T: PrimaryKeyedTable>(_: T.Type) async -> CKRecord? {
        let row =
          withErrorReporting {
            try database.read { db in
              try T.find(recordID: recordID).fetchOne(db)
            }
          }
          ?? nil
        guard let row
        else {
          syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
          missingRecord = recordID
          return nil
        }

        let record =
          metadata.lastKnownServerRecord
          ?? CKRecord(
            recordType: metadata.recordType,
            recordID: recordID
          )
        record.parent = metadata.parentRecordName.map { parentRecordName in
          CKRecord.Reference(
            recordID: CKRecord.ID(
              recordName: parentRecordName,
              zoneID: record.recordID.zoneID
            ),
            action: .none
          )
        }
        record.update(
          with: T(queryOutput: row),
          userModificationDate: metadata.userModificationDate
        )
        await refreshLastKnownServerRecord(record)
        sentRecord = recordID
        return record
      }
      return await open(table)
    }
    return batch
  }

  private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
    switch event.changeType {
    case .signIn:
      privateSyncEngine.state.add(pendingDatabaseChanges: [.saveZone(Self.defaultZone)])
      for table in tables {
        withErrorReporting(.sqliteDataCloudKitFailure) {
          let names: [String] = try database.read { db in
            func open<T: PrimaryKeyedTable>(_: T.Type) throws -> [String] {
              try T
                .select { SQLQueryExpression("\($0.primaryKey)", as: String.self) }
                .fetchAll(db)
            }
            return try open(table)
          }
          privateSyncEngine.state.add(
            pendingRecordZoneChanges: names.map {
              .saveRecord(
                CKRecord.ID(
                  recordName: $0,
                  zoneID: Self.defaultZone.zoneID
                )
              )
            }
          )
        }
      }
    case .signOut, .switchAccounts:
      withErrorReporting(.sqliteDataCloudKitFailure) {
        try deleteLocalData()
      }
    @unknown default:
      break
    }
  }

  private func handleStateUpdate(
    _ event: CKSyncEngine.Event.StateUpdate,
    syncEngine: CKSyncEngine
  ) {
    withErrorReporting(.sqliteDataCloudKitFailure) {
      try database.write { db in
        try StateSerialization.upsert(
          StateSerialization.Draft(
            scope: syncEngine.database.databaseScope,
            data: event.stateSerialization
          )
        )
        .execute(db)
      }
    }
  }

  private func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) {
    // TODO: Come back to this once we have zoneName in the metadata table.
    //    $isUpdatingWithServerRecord.withValue(true) {
    //      withErrorReporting(.sqliteDataCloudKitFailure) {
    //        try database.write { db in
    //          for deletion in event.deletions {
    //            if let table = tablesByName[deletion.zoneID.zoneName] {
    //              func open<T: PrimaryKeyedTable>(_: T.Type) {
    //                withErrorReporting(.sqliteDataCloudKitFailure) {
    //                  try T.delete().execute(db)
    //                }
    //              }
    //              open(table)
    //            }
    //          }
    //
    //          // TODO: Deal with modifications?
    //          _ = event.modifications
    //        }
    //      }
    //    }
  }

  package func handleFetchedRecordZoneChanges(
    modifications: [CKRecord],
    deletions: [(CKRecord.ID, CKRecord.RecordType)]
  ) {
    $isUpdatingWithServerRecord.withValue(true) {
      for modifiedRecord in modifications {
        mergeFromServerRecord(modifiedRecord)
        refreshLastKnownServerRecord(modifiedRecord)
      }

      for (recordID, recordType) in deletions {
        if let table = tablesByName[recordType] {
          func open<T: PrimaryKeyedTable>(_: T.Type) {
            withErrorReporting(.sqliteDataCloudKitFailure) {
              try database.write { db in
                try T.find(recordID: recordID)
                  .delete()
                  .execute(db)
              }
            }
          }
          open(table)
        } else {
          reportIssue(
            .sqliteDataCloudKitFailure.appending(
              """
              : No table to delete from: "\(recordType)"
              """
            )
          )
        }
      }
    }
  }

  private func handleSentRecordZoneChanges(
    _ event: CKSyncEngine.Event.SentRecordZoneChanges,
    syncEngine: CKSyncEngine
  ) {
    for savedRecord in event.savedRecords {
      refreshLastKnownServerRecord(savedRecord)
    }

    var newPendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] = []
    var newPendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
    defer {
      syncEngine.state.add(pendingDatabaseChanges: newPendingDatabaseChanges)
      syncEngine.state.add(pendingRecordZoneChanges: newPendingRecordZoneChanges)
    }
    for failedRecordSave in event.failedRecordSaves {
      let failedRecord = failedRecordSave.record

      func clearServerRecord() {
        withErrorReporting {
          try $isUpdatingWithServerRecord.withValue(true) {
            try database.write { db in
              try Metadata
                .find(recordID: failedRecord.recordID)
                .update { $0.lastKnownServerRecord = nil }
                .execute(db)
            }
          }
        }
      }

      switch failedRecordSave.error.code {
      case .serverRecordChanged:
        guard let serverRecord = failedRecordSave.error.serverRecord else { continue }
        mergeFromServerRecord(serverRecord)
        refreshLastKnownServerRecord(serverRecord)
        newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))

      case .zoneNotFound:
        let zone = CKRecordZone(zoneID: failedRecord.recordID.zoneID)
        // TODO: handle this
        //newPendingDatabaseChanges.append(.saveZone(zone))
        newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
        clearServerRecord()

      case .unknownItem:
        newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
        clearServerRecord()

      case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
        .operationCancelled, .batchRequestFailed:
        continue

      default:
        continue
      }
    }
    // TODO: handle event.failedRecordDeletes ? look at apple sample code
  }

  private func mergeFromServerRecord(_ record: CKRecord) {
    $isUpdatingWithServerRecord.withValue(true) {
      $currentZoneID.withValue(record.recordID.zoneID) {
        withErrorReporting(.sqliteDataCloudKitFailure) {
          let userModificationDate =
            try metadatabase.read { db in
              try Metadata.find(recordID: record.recordID).select(\.userModificationDate).fetchOne(
                db
              )
            }
            ?? nil
          guard let table = tablesByName[record.recordType]
          else {
            reportIssue(
              .sqliteDataCloudKitFailure.appending(
                """
                : No table to merge from: "\(record.recordType)"
                """
              )
            )
            return
          }
          guard
            let userModificationDate,
            userModificationDate > record.userModificationDate ?? .distantPast
          else {
            let columnNames = try database.read { db in
              try SQLQueryExpression(
                """
                SELECT "name" 
                FROM pragma_table_info(\(bind: table.tableName))    
                """,
                as: String.self
              )
              .fetchAll(db)
            }
            var query: QueryFragment = "INSERT INTO \(table) ("
            query.append(columnNames.map { "\(quote: $0)" }.joined(separator: ", "))
            query.append(") VALUES (")
            let encryptedValues = record.encryptedValues
            query.append(
              columnNames
                .map { columnName in
                  encryptedValues[columnName]?.queryFragment ?? "NULL"
                }
                .joined(separator: ", ")
            )
            func open<T: PrimaryKeyedTable>(_: T.Type) {
              query.append(") ON CONFLICT(\(quote: T.columns.primaryKey.name)) DO UPDATE SET")
            }
            open(table)
            query.append(
              columnNames
                .map {
                  """
                  \(quote: $0) = "excluded".\(quote: $0)
                  """
                }
                .joined(separator: ",")
            )
            try database.write { db in
              try SQLQueryExpression(query).execute(db)
              try Metadata
                .insert(Metadata(record: record)) {
                  $0.lastKnownServerRecord = record
                  $0.userModificationDate = record.userModificationDate
                }
                .execute(db)
            }
            return
          }
        }
      }
    }
  }

  private func refreshLastKnownServerRecord(_ record: CKRecord) {
    $currentZoneID.withValue(record.recordID.zoneID) {
      $isUpdatingWithServerRecord.withValue(true) {
        let metadata = metadataFor(recordID: record.recordID)

        func updateLastKnownServerRecord() {
          withErrorReporting(.sqliteDataCloudKitFailure) {
            try database.write { db in
              try Metadata
                .find(recordID: record.recordID)
                .update { $0.lastKnownServerRecord = record }
                .execute(db)
            }
          }
        }

        if let lastKnownDate = metadata?.lastKnownServerRecord?.modificationDate {
          if let recordDate = record.modificationDate, lastKnownDate < recordDate {
            updateLastKnownServerRecord()
          }
        } else {
          updateLastKnownServerRecord()
        }
      }
    }
  }

  private func metadataFor(recordID: CKRecord.ID) -> Metadata? {
    withErrorReporting(.sqliteDataCloudKitFailure) {
      try metadatabase.read { db in
        try Metadata.find(recordID: recordID).fetchOne(db)
      }
    }
      ?? nil
  }
}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
extension DatabaseFunction {
  fileprivate static func didUpdate(syncEngine: SyncEngine) -> Self {
    Self("didUpdate") { recordName, zoneName, ownerName in
      await syncEngine
        .didUpdate(
          recordName: recordName,
          zoneName: zoneName,
          ownerName: ownerName
        )
    }
  }

  fileprivate static func willDelete(syncEngine: SyncEngine) -> Self {
    return Self("willDelete") { recordName, zoneName, ownerName in
      await syncEngine.willDelete(
        recordName: recordName,
        zoneName: zoneName,
        ownerName: ownerName
      )
    }
  }

  fileprivate static var isUpdatingWithServerRecord: Self {
    Self(.sqliteDataCloudKitSchemaName + "_" + "isUpdatingWithServerRecord", argumentCount: 0) {
      _ in
      SharingGRDBCore.isUpdatingWithServerRecord
    }
  }

  fileprivate static var getZoneName: Self {
    Self(.sqliteDataCloudKitSchemaName + "_" + "getZoneName", argumentCount: 0) { _ in
      SharingGRDBCore.currentZoneID?.zoneName
    }
  }

  fileprivate static var getOwnerName: Self {
    Self(.sqliteDataCloudKitSchemaName + "_" + "getOwnerName", argumentCount: 0) { _ in
      SharingGRDBCore.currentZoneID?.ownerName
    }
  }

  private convenience init(
    _ name: String,
    function: @escaping @Sendable (String, String, String) async -> Void
  ) {
    self.init(.sqliteDataCloudKitSchemaName + "_" + name, argumentCount: 3) { arguments in
      guard
        let recordName = String.fromDatabaseValue(arguments[0]),
        let zoneName = String.fromDatabaseValue(arguments[1]),
        let ownerName = String.fromDatabaseValue(arguments[2])
      else {
        return nil
      }
      // TODO: can we get rid of task by making stuff in actor non-isolated?
      Task { await function(recordName, zoneName, ownerName) }
      return nil
    }
  }
}

// TODO: Rename to isUpdatingFromServer / isHandlingServerUpdates
@TaskLocal private var isUpdatingWithServerRecord = false
@available(iOS 16.4, macOS 13.3, tvOS 16.4, watchOS 9, *)
@TaskLocal private var currentZoneID: CKRecordZone.ID?

extension String {
  package static let sqliteDataCloudKitSchemaName = "sqlitedata_icloud"
  fileprivate static let sqliteDataCloudKitFailure = "SharingGRDB CloudKit Failure"
}

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
extension URL {
  fileprivate static func metadatabase(container: CKContainer) -> Self {
    applicationSupportDirectory.appending(
      component: "\(container.containerIdentifier.map { "\($0)." } ?? "")sqlite-data-icloud.sqlite"
    )
  }
}
