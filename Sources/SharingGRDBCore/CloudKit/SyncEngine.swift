#if canImport(CloudKit)
import CloudKit
import ConcurrencyExtras
import OSLog

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
public final class SyncEngine: Sendable {
  public static nonisolated let defaultZone = CKRecordZone(
    zoneName: "co.pointfree.SQLiteData.defaultZone"
  )

  let database: any DatabaseWriter
  let logger: Logger
  let metadatabase: any DatabaseReader
  let tables: [any StructuredQueriesCore.PrimaryKeyedTable<UUID>.Type]
  let privateTables: [any StructuredQueriesCore.PrimaryKeyedTable<UUID>.Type]
  let tablesByName: [String: any StructuredQueriesCore.PrimaryKeyedTable<UUID>.Type]
  let foreignKeysByTableName: [String: [ForeignKey]]
  let syncEngines = LockIsolated<SyncEngines>(SyncEngines())
  let defaultSyncEngines:
    @Sendable (any DatabaseReader, SyncEngine)
      -> (private: any SyncEngineProtocol, shared: any SyncEngineProtocol)
  let container: any CloudContainerProtocol

  public convenience init(
    container: CKContainer,
    database: any DatabaseWriter,
    logger: Logger = Logger(subsystem: "SQLiteData", category: "CloudKit"),
    tables: [any PrimaryKeyedTable<UUID>.Type],
    privateTables: [any PrimaryKeyedTable<UUID>.Type] = []
  ) throws {
    try self.init(
      container: container,
      defaultSyncEngines: { database, syncEngine in
        (
          private: CKSyncEngine(
            CKSyncEngine.Configuration(
              database: container.privateCloudDatabase,
              stateSerialization: try? database.read { db in  // TODO: write test for this
                try StateSerialization.find(CKDatabase.Scope.private).select(\.data).fetchOne(db)
              },
              delegate: syncEngine
            )
          ),
          shared: CKSyncEngine(
            CKSyncEngine.Configuration(
              database: container.sharedCloudDatabase,
              stateSerialization: try? database.read { db in  // TODO: write test for this
                try StateSerialization.find(CKDatabase.Scope.shared).select(\.data).fetchOne(db)
              },
              delegate: syncEngine
            )
          )
        )
      },
      database: database,
      logger: logger,
      metadatabaseURL: URL.metadatabase(containerIdentifier: container.containerIdentifier),
      tables: tables,
      privateTables: privateTables
    )
    _ = try setUpSyncEngine(
      database: database,
      metadatabase: metadatabase
    )
  }

  package convenience init(
    container: any CloudContainerProtocol,
    privateSyncEngine: any SyncEngineProtocol,
    sharedSyncEngine: any SyncEngineProtocol,
    database: any DatabaseWriter,
    metadatabaseURL: URL,
    tables: [any PrimaryKeyedTable<UUID>.Type],
    privateTables: [any PrimaryKeyedTable<UUID>.Type] = []
  ) async throws {
    try self.init(
      container: container,
      defaultSyncEngines: { _, _ in (privateSyncEngine, sharedSyncEngine) },
      database: database,
      logger: Logger(.disabled),
      metadatabaseURL: metadatabaseURL,
      tables: tables,
      privateTables: privateTables
    )
    try await setUpSyncEngine(database: database, metadatabase: metadatabase)?.value
  }

  private init(
    container: any CloudContainerProtocol,
    defaultSyncEngines: @escaping @Sendable (
      any DatabaseReader,
      SyncEngine
    ) -> (private: any SyncEngineProtocol, shared: any SyncEngineProtocol),
    database: any DatabaseWriter,
    logger: Logger,
    metadatabaseURL: URL,
    tables: [any PrimaryKeyedTable<UUID>.Type],
    privateTables: [any PrimaryKeyedTable<UUID>.Type] = []
  ) throws {
    try validateSchema(tables: tables, database: database)
    // TODO: Explain why / link to documentation?
    precondition(
      !database.configuration.foreignKeysEnabled,
      """
      Foreign key support must be disabled to synchronize with CloudKit.
      """
    )
    self.container = container
    self.defaultSyncEngines = defaultSyncEngines
    self.database = database
    self.logger = logger
    self.metadatabase = try defaultMetadatabase(logger: logger, url: metadatabaseURL)
    self.tables = Set((tables + privateTables).map(HashablePrimaryKeyedTableType.init)).map(\.type)
    self.privateTables = privateTables
    self.tablesByName = Dictionary(uniqueKeysWithValues: self.tables.map { ($0.tableName, $0) })
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
  }

  package func setUpSyncEngine() async throws {
    try await setUpSyncEngine(database: database, metadatabase: metadatabase)?.value
  }

  nonisolated func setUpSyncEngine(
    database: any DatabaseWriter,
    metadatabase: any DatabaseReader
  ) throws -> Task<Void, Never>? {
    try database.write { db in
      let hasAttachedMetadatabase: Bool =
      try SQLQueryExpression(
          """
          SELECT count(*) 
          FROM pragma_database_list 
          WHERE "name" = \(bind: String.sqliteDataCloudKitSchemaName)
          """,
          as: Int.self
      )
      .fetchOne(db) == 1
      if !hasAttachedMetadatabase {
        try SQLQueryExpression(
          """
          ATTACH DATABASE \(bind: metadatabase.path) AS \(quote: .sqliteDataCloudKitSchemaName)
          """
        )
        .execute(db)
      }
      db.add(function: .datetime)
      db.add(function: .isUpdatingWithServerRecord)
      db.add(function: .didUpdate(syncEngine: self))
      db.add(function: .didDelete(syncEngine: self))

      for trigger in SyncMetadata.callbackTriggers {
        try trigger.execute(db)
      }

      for table in tables {
        try table.createTriggers(
          foreignKeysByTableName: foreignKeysByTableName,
          tablesByName: tablesByName,
          db: db
        )
      }
    }

    let (privateSyncEngine, sharedSyncEngine) = defaultSyncEngines(metadatabase, self)
    syncEngines.withValue {
      $0 = SyncEngines(
        private: privateSyncEngine,
        shared: sharedSyncEngine
      )
    }
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
    let recordTypesToFetch = currentRecordTypes.compactMap { currentRecordType in
      guard
        let existingRecordType = previousRecordTypes.first(where: { previousRecordType in
          currentRecordType.tableName == previousRecordType.tableName
        })
      else { return (currentRecordType, isNewTable: true) }
      return existingRecordType.schema == currentRecordType.schema
      ? nil
      : (currentRecordType, isNewTable: false)
    }

    guard !recordTypesToFetch.isEmpty
    else { return nil }

    withErrorReporting(.sqliteDataCloudKitFailure) {
      try database.write { db in
        for (recordType, isNewTable) in recordTypesToFetch {
          try RecordType
            .upsert { RecordType.Draft(recordType) }
            .execute(db)
          if isNewTable, let table = tablesByName[recordType.tableName] {
            func open<T: PrimaryKeyedTable<UUID>>(_: T.Type) throws {
              try T
                .update { $0.primaryKey = $0.primaryKey }
                .execute(db)
            }
            try open(table)
          }
        }
      }
    }

    return Task {
      await withErrorReporting(.sqliteDataCloudKitFailure) {
        // TODO: comment this out and see if things still work
        try await fetchChanges()
        try await fetchChangesFromSchemaChange(
          recordTypesChanged: recordTypesToFetch.filter { !$0.isNewTable }.map(\.0)
        )
      }
    }
  }

  private func fetchChangesFromSchemaChange(recordTypesChanged: [RecordType]) async throws {
    let lastKnownServerRecords = try {
      try metadatabase.read { db in
        try SyncMetadata
          .where {
            $0.recordType.in(recordTypesChanged.map(\.tableName)) && $0.lastKnownServerRecord.isNot(nil)
          }
          .select {
            SQLQueryExpression(
              "\($0.lastKnownServerRecord)",
              as: CKRecord.DataRepresentation.self
            )
          }
          .fetchAll(db)
      }
    }()

    let recordIDs = lastKnownServerRecords.map(\.recordID)
    let recordIDsByDatabase = Dictionary(grouping: recordIDs) {
      AnyCloudDatabase(container.database(for: $0))
    }
    for (database, recordIDs) in recordIDsByDatabase {
      let results = try await database.records(for: recordIDs)
      for (_, result) in results {
        switch result {
        case .success(let record):
          upsertFromServerRecord(record)
          break
        case .failure(let error):
          reportIssue(error)
          break
        }
      }
    }
  }

  package func tearDownSyncEngine() async throws {
    let syncEngines = syncEngines.withValue(\.self)
    async let privateCancellation: Void? = syncEngines.private?.cancelOperations()
    async let sharedCancellation: Void? = syncEngines.shared?.cancelOperations()

    try await database.write { db in
      for table in self.tables {
        try table.dropTriggers(foreignKeysByTableName: self.foreignKeysByTableName, db: db)
      }
      for trigger in SyncMetadata.callbackTriggers.reversed() {
        try trigger.drop().execute(db)
      }
      db.remove(function: .didDelete(syncEngine: self))
      db.remove(function: .didUpdate(syncEngine: self))
      db.remove(function: .isUpdatingWithServerRecord)
      db.remove(function: .datetime)
    }
    try await database.write { db in
      // TODO: Do an `.erase()` + re-migrate
      try SyncMetadata.delete().execute(db)
      try RecordType.delete().execute(db)
      try StateSerialization.delete().execute(db)
    }
    _ = await (privateCancellation, sharedCancellation)
  }

  // TODO: resendAll() ?

  public func fetchChanges() async throws {
    let syncEngines = syncEngines.withValue(\.self)
    try await syncEngines.private?.fetchChanges()
    try await syncEngines.shared?.fetchChanges()
  }

  public func deleteLocalData() async throws {
    try await tearDownSyncEngine()
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
    try await setUpSyncEngine()
  }

  func didUpdate(recordName: SyncMetadata.RecordName, zoneID: CKRecordZone.ID?) {
    let zoneID = zoneID ?? Self.defaultZone.zoneID
    let syncEngine = self.syncEngines.withValue {
      zoneID.ownerName == CKCurrentUserDefaultName ? $0.private : $0.shared
    }
    syncEngine?.state.add(
      pendingRecordZoneChanges: [
        .saveRecord(
          CKRecord.ID(
            recordName: recordName.rawValue,
            zoneID: zoneID
          )
        )
      ]
    )
  }

  func didDelete(recordName: SyncMetadata.RecordName, zoneID: CKRecordZone.ID?) {
    let zoneID = zoneID ?? Self.defaultZone.zoneID
    let syncEngine = self.syncEngines.withValue {
      zoneID.ownerName == CKCurrentUserDefaultName ? $0.private : $0.shared
    }
    syncEngine?.state.add(
      pendingRecordZoneChanges: [
        .deleteRecord(
          CKRecord.ID(
            recordName: recordName.rawValue,
            zoneID: zoneID
          )
        )
      ]
    )
  }
}

extension PrimaryKeyedTable<UUID> {
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  fileprivate static func createTriggers(
    foreignKeysByTableName: [String: [ForeignKey]],
    tablesByName: [String: any PrimaryKeyedTable<UUID>.Type],
    db: Database
  ) throws {
    let parentForeignKey =
      foreignKeysByTableName[tableName]?.count == 1
      ? foreignKeysByTableName[tableName]?.first
      : nil

    for trigger in metadataTriggers(parentForeignKey: parentForeignKey) {
      try trigger.execute(db)
    }

    let foreignKeys = foreignKeysByTableName[tableName] ?? []
    for foreignKey in foreignKeys {
      guard let parent = tablesByName[foreignKey.table] else {
        reportIssue("TODO")
        continue
      }
      try foreignKey.createTriggers(Self.self, belongsTo: parent, db: db)
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  fileprivate static func dropTriggers(
    foreignKeysByTableName: [String: [ForeignKey]],
    db: Database
  ) throws {
    let foreignKeys = foreignKeysByTableName[tableName] ?? []
    for foreignKey in foreignKeys.reversed() {
      try foreignKey.dropTriggers(for: Self.self, db: db)
    }

    for trigger in metadataTriggers(parentForeignKey: nil).reversed() {
      try trigger.drop().execute(db)
    }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngine: CKSyncEngineDelegate {
  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    logger.log(event, syncEngine: syncEngine)

    switch event {
    case .accountChange(let event):
      await handleAccountChange(event)
    case .stateUpdate(let event):
      handleStateUpdate(event, syncEngine: syncEngine)
    case .fetchedDatabaseChanges(let event):
      handleFetchedDatabaseChanges(event)
    case .sentDatabaseChanges:
      break
    case .fetchedRecordZoneChanges(let event):
      await handleFetchedRecordZoneChanges(
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
    await _nextRecordZoneChangeBatch(
      SendChangesContext(context: context),
      syncEngine: syncEngine
    )
  }

  package func _nextRecordZoneChangeBatch(
    _ context: SendChangesContext,
    syncEngine: any SyncEngineProtocol
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
    // TODO: why did we do this again? can we test it?
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

    let batch = await syncEngine.recordZoneChangeBatch(pendingChanges: changes) { recordID in
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

      guard
        let recordName = SyncMetadata.RecordName(recordID: recordID),
        let metadata = metadataFor(recordName: recordName)
      else {
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        return nil
      }
      guard let table = tablesByName[metadata.recordType]
      else {
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
        missingTable = recordID
        return nil
      }
      func open<T: PrimaryKeyedTable<UUID>>(_: T.Type) async -> CKRecord? {
        let row =
          withErrorReporting {
            try database.read { db in
              try T.find(recordName.id).fetchOne(db)
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
        record.parent = metadata.parentRecordName.flatMap { parentRecordName in
          guard !privateTables.contains(where: { $0.tableName == parentRecordName.recordType })
          else { return nil }
          return CKRecord.Reference(
            recordID: CKRecord.ID(
              recordName: parentRecordName.rawValue,
              zoneID: record.recordID.zoneID
            ),
            action: .none
          )
        }
        record.update(
          with: T(queryOutput: row),
          userModificationDate: metadata.userModificationDate
        )
        refreshLastKnownServerRecord(record)
        sentRecord = recordID
        return record
      }
      return await open(table)
    }
    return batch
  }

  private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) async {
    switch event.changeType {
    case .signIn:
      syncEngines.withValue {
        $0.private?.state.add(pendingDatabaseChanges: [.saveZone(Self.defaultZone)])
      }
      for table in tables {
        withErrorReporting(.sqliteDataCloudKitFailure) {
          let recordNames = try database.read { db in
            func open<T: PrimaryKeyedTable<UUID>>(_: T.Type) throws -> [SyncMetadata.RecordName] {
              try T
                .select(\.primaryKey)
                .fetchAll(db)
                .map { T.recordName(for: $0) }
            }
            return try open(table)
          }
          syncEngines.withValue {
            $0.private?.state.add(
              pendingRecordZoneChanges: recordNames.map {
                .saveRecord(
                  CKRecord.ID(
                    recordName: $0.rawValue,
                    zoneID: Self.defaultZone.zoneID
                  )
                )
              }
            )
          }
        }
      }
    case .signOut, .switchAccounts:
      await withErrorReporting(.sqliteDataCloudKitFailure) {
        try await deleteLocalData()
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
        try StateSerialization.upsert {
          StateSerialization.Draft(
            scope: syncEngine.database.databaseScope,
            data: event.stateSerialization
          )
        }
        .execute(db)
      }
    }
  }

  private func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) {
    // TODO: How to handle this?
    $isUpdatingWithServerRecord.withValue(true) {
      withErrorReporting(.sqliteDataCloudKitFailure) {
        try database.write { db in
          for deletion in event.deletions {
            // if let table = tablesByName[deletion.zoneID.zoneName] {
            //   func open<T: PrimaryKeyedTable>(_: T.Type) {
            //     withErrorReporting(.sqliteDataCloudKitFailure) {
            //       try T.delete().execute(db)
            //     }
            //   }
            //   open(table)
          }
        }

        // TODO: Deal with modifications?
        _ = event.modifications
      }
    }
  }

  package func handleFetchedRecordZoneChanges(
    modifications: [CKRecord],
    deletions: [(CKRecord.ID, CKRecord.RecordType)]
  ) async {
    await $isUpdatingWithServerRecord.withValue(true) {
      for record in modifications {
        if let share = record as? CKShare {
          await withErrorReporting {
            try await cacheShare(share)
          }
        } else {
          upsertFromServerRecord(record)
          refreshLastKnownServerRecord(record)
        }
        if let shareReference = record.share,
          let shareRecord = try? await container.database(for: shareReference.recordID)
            .record(for: shareReference.recordID),
          let share = shareRecord as? CKShare
        {
          await withErrorReporting {
            try await cacheShare(share)
          }
        }
      }

      for (recordID, recordType) in deletions {
        if let table = tablesByName[recordType] {
          guard let recordName = SyncMetadata.RecordName(recordID: recordID)
          else {
            reportIssue(
              """
              Received 'recordName' in invalid format: \(recordID.recordName)

              'recordName' should be formatted as "uuid:tableName". 
              """
            )
            continue
          }
          func open<T: PrimaryKeyedTable<UUID>>(_: T.Type) {
            withErrorReporting(.sqliteDataCloudKitFailure) {
              try database.write { db in
                try T.find(recordName.id)
                  .delete()
                  .execute(db)
              }
            }
          }
          open(table)
        } else if recordType == CKRecord.SystemType.share {
          withErrorReporting {
            try deleteShare(recordID: recordID, recordType: recordType)
          }
        } else {
          // TODO: Should we be reporting this? What if another device deletes from a table this device doesn't know about?
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
      guard let recordName = SyncMetadata.RecordName(rawValue: failedRecord.recordID.recordName)
      else {
        reportIssue(
          """
          Attempted to delete record with invalid 'recordName': \(failedRecord.recordID.recordName)

          'recordName' should be formatted as "uuid:tableName".
          """
        )
        continue
      }

      func clearServerRecord() {
        withErrorReporting {
          try $isUpdatingWithServerRecord.withValue(true) {
            try database.write { db in
              try SyncMetadata
                .find(recordName)
                .update { $0.lastKnownServerRecord = nil }
                .execute(db)
            }
          }
        }
      }

      switch failedRecordSave.error.code {
      case .serverRecordChanged:
        guard let serverRecord = failedRecordSave.error.serverRecord else { continue }
        upsertFromServerRecord(serverRecord)
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

  private func cacheShare(_ share: CKShare) async throws {
    guard let url = share.url
    else { return }

    guard let metadata = try? await container.shareMetadata(
      for: url,
      shouldFetchRootRecord: true
    )
    else {
      // TODO: should we delete this record if it doesn't exist in the container?
      return
    }

    guard let rootRecord = metadata.rootRecord
    else { return }
    guard let recordName = SyncMetadata.RecordName(recordID: rootRecord.recordID)
    else {
      reportIssue(
        """
        Attempted to delete record with invalid 'recordName': \(rootRecord.recordID.recordName)

        'recordName' should be formatted as "uuid:tableName".
        """
      )
      return
    }

    try {
      try database.write { db in
        try SyncMetadata
          .find(recordName)
          .update { $0.share = share }
          .execute(db)
      }
    }()
  }

  private func deleteShare(recordID: CKRecord.ID, recordType: String) throws {
    // TODO: more efficient way to do this?
    try database.write { db in
      let metadata =
        try SyncMetadata
        .where { $0.share.isNot(nil) }
        .fetchAll(db)
        .first(where: { $0.share?.recordID == recordID }) ?? nil
      guard let metadata
      else { return }
      try SyncMetadata.find(metadata.recordName)
        .update { $0.share = nil }
        .execute(db)
    }
  }

  private func upsertFromServerRecord(_ record: CKRecord) {
    $isUpdatingWithServerRecord.withValue(true) {
      withErrorReporting(.sqliteDataCloudKitFailure) {
        guard let table = tablesByName[record.recordType]
        else {
          // TODO: Should we be reporting this? What if another device makes changes to a table this device doesn't know about?
          reportIssue(
            .sqliteDataCloudKitFailure.appending(
              """
              : No table to merge from: "\(record.recordType)"
              """
            )
          )
          return
        }
        guard let recordName = SyncMetadata.RecordName(recordID: record.recordID)
        else {
          reportIssue(
            """
            Attempted to delete record with invalid 'recordName': \(record.recordID.recordName)

            'recordName' should be formatted as "uuid:tableName".
            """
          )
          return
        }
        let userModificationDate =
          try metadatabase.read { db in
            try SyncMetadata.find(recordName).select(\.userModificationDate).fetchOne(
              db
            )
          }
          ?? nil
        guard
          let userModificationDate,
          userModificationDate > record.userModificationDate ?? .distantPast
        else {
          // TODO: This should be fetched early and held onto (like 'ForeignKey')
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
                if let asset = record[columnName] as? CKAsset {
                  return (try? asset.fileURL.map { try Data(contentsOf: $0) })?
                    .queryFragment ?? "NULL"
                } else {
                  return encryptedValues[columnName]?.queryFragment ?? "NULL"
                }
              }
              .joined(separator: ", ")
          )
          func open<T: PrimaryKeyedTable>(_: T.Type) -> String {
            T.columns.primaryKey.name
          }
          let primaryKeyName = open(table)
          query.append(") ON CONFLICT(\(quote: primaryKeyName)) DO UPDATE SET ")

          query.append(
            columnNames
              .filter { columnName in columnName != primaryKeyName }
              .map {
                """
                \(quote: $0) = "excluded".\(quote: $0)
                """
              }
              .joined(separator: ",")
          )
          // TODO: Append more ON CONFLICT clauses for each unique constraint?
          // TODO: Use WHERE to scope the update?
          guard let metadata = SyncMetadata(record: record)
          else {
            reportIssue("???")
            return
          }
          try database.write { db in
            try SQLQueryExpression(query).execute(db)
            try SyncMetadata
              .insert {
                metadata
              } onConflictDoUpdate: {
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

  private func refreshLastKnownServerRecord(_ record: CKRecord) {
    $isUpdatingWithServerRecord.withValue(true) {
      guard let recordName = SyncMetadata.RecordName(recordID: record.recordID)
      else {
        reportIssue(
          """
          Attempted to delete record with invalid 'recordName': \(record.recordID.recordName)

          'recordName' should be formatted as "uuid:tableName".
          """
        )
        return
      }
      let metadata = metadataFor(recordName: recordName)

      func updateLastKnownServerRecord() {
        withErrorReporting(.sqliteDataCloudKitFailure) {
          try database.write { db in
            try SyncMetadata
              .find(recordName)
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

  private func metadataFor(recordName: SyncMetadata.RecordName) -> SyncMetadata? {
    withErrorReporting(.sqliteDataCloudKitFailure) {
      try metadatabase.read { db in
        try SyncMetadata.find(recordName).fetchOne(db)
      }
    }
      ?? nil
  }
}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
extension DatabaseFunction {
  fileprivate static func didUpdate(syncEngine: SyncEngine) -> Self {
    Self("didUpdate") { recordName, zoneID in
      syncEngine.didUpdate(
        recordName: recordName,
        zoneID: zoneID
      )
    }
  }

  fileprivate static func didDelete(syncEngine: SyncEngine) -> Self {
    return Self("didDelete") { recordName, zoneID in
      syncEngine.didDelete(recordName: recordName, zoneID: zoneID)
    }
  }

  fileprivate static var datetime: Self {
    Self(.sqliteDataCloudKitSchemaName + "_datetime", argumentCount: 0) { _ in
      @Dependency(\.date.now) var now
      return now.formatted(
        .iso8601
          .year().month().day()
          .dateTimeSeparator(.space)
          .time(includingFractionalSeconds: true)
      )
    }
  }

  fileprivate static var isUpdatingWithServerRecord: Self {
    Self(.sqliteDataCloudKitSchemaName + "_" + "isUpdatingWithServerRecord", argumentCount: 0) {
      _ in
      SharingGRDBCore.isUpdatingWithServerRecord
    }
  }

  private convenience init(
    _ name: String,
    function: @escaping @Sendable (SyncMetadata.RecordName, CKRecordZone.ID?) -> Void
  ) {
    self.init(.sqliteDataCloudKitSchemaName + "_" + name, argumentCount: 2) { arguments in
      guard
        let recordName = String.fromDatabaseValue(arguments[0])
      else {
        return nil
      }
      guard let recordName = SyncMetadata.RecordName(rawValue: recordName)
      else {
        reportIssue(
          """
          Received 'recordName' in invalid format: \(recordName)

          'recordName' should be formatted as "uuid:tableName". 
          """
        )
        return nil
      }
      let zoneID = try Data.fromDatabaseValue(arguments[1]).flatMap {
        let coder = try NSKeyedUnarchiver(forReadingFrom: $0)
        coder.requiresSecureCoding = true
        return CKRecord(coder: coder)?.recordID.zoneID
      }
      function(recordName, zoneID)
      return nil
    }
  }
}

// TODO: Rename to isUpdatingFromServer / isHandlingServerUpdates
@TaskLocal private var isUpdatingWithServerRecord = false

extension String {
  package static let sqliteDataCloudKitSchemaName = "sqlitedata_icloud"
  fileprivate static let sqliteDataCloudKitFailure = "SharingGRDB CloudKit Failure"
}

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
extension URL {
  package static func metadatabase(containerIdentifier: String?) throws -> Self {
    @Dependency(\.context) var context
    try FileManager.default.createDirectory(
      at: .applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    let base: URL = context == .live
    ? .applicationSupportDirectory
    : .temporaryDirectory
    return base.appending(
      component: "\(containerIdentifier.map { "\($0)." } ?? "")sqlite-data-icloud.sqlite"
    )
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
struct SyncEngines {
  let _private: (any SyncEngineProtocol)?
  let _shared: (any SyncEngineProtocol)?
  init() {
    _private = nil
    _shared = nil
  }
  init(private: any SyncEngineProtocol, shared: any SyncEngineProtocol) {
    self._private = `private`
    self._shared = shared
  }
  var `private`: (any SyncEngineProtocol)? {
    guard let _private
    else {
      reportIssue("Private sync engine has not been set.")
      return nil
    }
    return _private
  }
  var `shared`: (any SyncEngineProtocol)? {
    guard let _shared
    else {
      reportIssue("Shared sync engine has not been set.")
      return nil
    }
    return _shared
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension Database {
  /// Attaches the metadatabase to an existing database connection.
  ///
  /// Invoke this method when preparing your database connection in order to allow querying the
  /// ``SyncMetadata`` table (see <doc:CloudKit#Accessing-CloudKit-metadata> for more info):
  ///
  /// ```swift
  /// func appDatabase() -> any DatabaseWriter {
  ///   var configuration = Configuration()
  ///   configuration.prepareDatabase = { db in
  ///     db.attachMetadatabase(containerIdentifier: "iCloud.my.company.MyApp")
  ///     …
  ///   }
  /// }
  /// ```
  ///
  /// See <doc:PreparingDatabase> for more information on preparing your database.
  ///
  /// - Parameter containerIdentifier: The identifier of the CloudKit container used to synchronize
  ///                                  data.
  public func attachMetadatabase(containerIdentifier: String) throws {
    let url = try URL.metadatabase(containerIdentifier: containerIdentifier)
    let path = url.path(percentEncoded: false)
    try FileManager.default.createDirectory(
      at: .applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    _ = try DatabasePool(path: path).write { db in
      try SQLQueryExpression("SELECT 1").execute(db)
    }
    try SQLQueryExpression(
      """
      ATTACH DATABASE \(bind: path) AS \(quote: .sqliteDataCloudKitSchemaName)
      """
    )
    .execute(self)
  }
}

private func validateSchema(
  tables: [any PrimaryKeyedTable.Type],
  database: any DatabaseReader
) throws {
  try database.read { db in
    for table in tables {
      //      // TODO: write tests for this
      //      let columnsWithUniqueConstraints =
      //        try SQLQueryExpression(
      //          """
      //          SELECT "name" FROM pragma_index_list(\(quote: table.tableName, delimiter: .text))
      //          WHERE "unique" = 1 AND "origin" <> 'pk'
      //          """,
      //          as: String.self
      //        )
      //        .fetchAll(db)
      //      if !columnsWithUniqueConstraints.isEmpty {
      //        throw UniqueConstraintDisallowed(table: table, columns: columnsWithUniqueConstraints)
      //      }

      //      // TODO: write tests for this
      //      let nonNullColumnsWithNoDefault =
      //        try SQLQueryExpression(
      //          """
      //          SELECT "name" FROM pragma_table_info(\(quote: table.tableName, delimiter: .text))
      //          WHERE "notnull" = 1 AND "dflt_value" IS NULL
      //          """,
      //          as: String.self
      //        )
      //        .fetchAll(db)
      //      if !nonNullColumnsWithNoDefault.isEmpty {
      //        throw NonNullColumnMustHaveDefault(table: table, columns: nonNullColumnsWithNoDefault)
      //      }
    }
  }
}

public struct UniqueConstraintDisallowed: Error {
  let localizedDescription: String
  init(table: any PrimaryKeyedTable.Type, columns: [String]) {
    localizedDescription = """
      Table '\(table.tableName)' has column\(columns.count == 1 ? "" : "s") with unique \
      constraints: \(columns.map { "'\($0)'" }.joined(separator: ", "))
      """
  }
}
public struct NonNullColumnMustHaveDefault: Error {
  let localizedDescription: String
  init(table: any PrimaryKeyedTable.Type, columns: [String]) {
    localizedDescription = """
      Table '\(table.tableName)' has non-null column\(columns.count == 1 ? "" : "s") with no \
      default: \(columns.map { "'\($0)'" }.joined(separator: ", "))
      """
  }
}

private struct HashablePrimaryKeyedTableType: Hashable {
  let type: any PrimaryKeyedTable<UUID>.Type
  func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(type))
  }
  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.type == rhs.type
  }
}
#endif
