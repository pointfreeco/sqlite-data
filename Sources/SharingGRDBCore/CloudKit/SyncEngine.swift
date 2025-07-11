#if canImport(CloudKit)
  import CloudKit
  import ConcurrencyExtras
  import CustomDump
  import OSLog

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public final class SyncEngine: Sendable {
    public static nonisolated let defaultZone = CKRecordZone(
      zoneName: "co.pointfree.SQLiteData.defaultZone"
    )

    package let userDatabase: UserDatabase
    package let logger: Logger
    package let metadatabase: any DatabaseReader
    package let tables: [any PrimaryKeyedTable<UUID>.Type]
    package let privateTables: [any PrimaryKeyedTable<UUID>.Type]
    let tablesByName: [String: any PrimaryKeyedTable<UUID>.Type]
    private let tablesByOrder: [String: Int]
    let foreignKeysByTableName: [String: [ForeignKey]]
    package let syncEngines = LockIsolated<SyncEngines>(SyncEngines())
    let defaultSyncEngines:
      @Sendable (any DatabaseReader, SyncEngine)
        -> (private: any SyncEngineProtocol, shared: any SyncEngineProtocol)
    package let container: any CloudContainer

    public convenience init(
      container: CKContainer,
      database: any DatabaseWriter,
      logger: Logger = Logger(subsystem: "SQLiteData", category: "CloudKit"),
      tables: [any PrimaryKeyedTable<UUID>.Type],
      privateTables: [any PrimaryKeyedTable<UUID>.Type] = []
    ) throws {
      let userDatabase = UserDatabase(database: database)
      try self.init(
        container: container,
        defaultSyncEngines: { metadatabase, syncEngine in
          (
            private: CKSyncEngine(
              CKSyncEngine.Configuration(
                database: container.privateCloudDatabase,
                stateSerialization: try? metadatabase.read { db in
                  try StateSerialization
                    .find(BindQueryExpression(CKDatabase.Scope.private))
                    .select(\.data)
                    .fetchOne(db)
                },
                delegate: syncEngine
              )
            ),
            shared: CKSyncEngine(
              CKSyncEngine.Configuration(
                database: container.sharedCloudDatabase,
                stateSerialization: try? metadatabase.read { db in
                  try StateSerialization
                    .find(BindQueryExpression(CKDatabase.Scope.shared))
                    .select(\.data)
                    .fetchOne(db)
                },
                delegate: syncEngine
              )
            )
          )
        },
        userDatabase: userDatabase,
        logger: logger,
        metadatabaseURL: URL.metadatabase(containerIdentifier: container.containerIdentifier),
        tables: tables,
        privateTables: privateTables
      )
      _ = try setUpSyncEngine(
        userDatabase: userDatabase,
        metadatabase: metadatabase
      )
    }

    package init(
      container: any CloudContainer,
      defaultSyncEngines: @escaping @Sendable (
        any DatabaseReader,
        SyncEngine
      ) -> (private: any SyncEngineProtocol, shared: any SyncEngineProtocol),
      userDatabase: UserDatabase,
      logger: Logger,
      metadatabaseURL: URL,
      tables: [any PrimaryKeyedTable<UUID>.Type],
      privateTables: [any PrimaryKeyedTable<UUID>.Type] = []
    ) throws {
      try validateSchema(tables: tables, userDatabase: userDatabase)
      // TODO: Explain why / link to documentation?
      precondition(
        !userDatabase.configuration.foreignKeysEnabled,
        """
        Foreign key support must be disabled to synchronize with CloudKit.
        """
      )
      self.container = container
      self.defaultSyncEngines = defaultSyncEngines
      self.userDatabase = userDatabase
      self.logger = logger
      self.metadatabase = try defaultMetadatabase(logger: logger, url: metadatabaseURL)
      let tables = Set((tables + privateTables).map(HashablePrimaryKeyedTableType.init))
        .map(\.type)
      self.tables = tables
      self.privateTables = privateTables

      let allTables = try userDatabase.read { db in
        try SQLQueryExpression(
          """
          SELECT "name" FROM "sqlite_master" WHERE "type" = 'table'
          """,
          as: String.self
        )
        .fetchAll(db)
      }

      self.tablesByName = Dictionary(uniqueKeysWithValues: self.tables.map { ($0.tableName, $0) })
      self.foreignKeysByTableName = Dictionary(
        uniqueKeysWithValues: try userDatabase.read { db in
          try allTables.map { table -> (String, [ForeignKey]) in
            (
              table,
              try ForeignKey.all(table).fetchAll(db)
            )
          }
        }
      )
      tablesByOrder = try SharingGRDBCore.tablesByOrder(
        userDatabase: userDatabase,
        tables: tables,
        tablesByName: tablesByName
      )
    }

    @TaskLocal package static var _isUpdatingRecord = false

    package func setUpSyncEngine() async throws {
      try await setUpSyncEngine(userDatabase: userDatabase, metadatabase: metadatabase)?.value
    }

    nonisolated package func setUpSyncEngine(
      userDatabase: UserDatabase,
      metadatabase: any DatabaseReader
    ) throws -> Task<Void, Never>? {
      try userDatabase.write { db in
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
        db.add(function: .syncEngineIsUpdatingRecord)
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
        for (childTableName, foreignKeys) in foreignKeysByTableName {
          for foreignKey in foreignKeys {
            try foreignKey.createTriggers(childTableName, belongsTo: foreignKey.table, db: db)
          }
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
      let currentRecordTypes = try userDatabase.read { db in
        let namesAndSchemas = try SQLiteSchema.all
          .fetchAll(db)
          .filter { $0.type == "table" }
        return try namesAndSchemas.compactMap { schema -> RecordType? in
          guard let sql = schema.sql
          else { return nil }
          return RecordType(
            tableName: schema.name,
            schema: sql,
            tableInfo: Set(try TableInfo.all(schema.name).fetchAll(db))
          )
        }
      }
      cacheUserTables(recordTypes: currentRecordTypes)
      let previousRecordTypeByTableName = Dictionary(
        uniqueKeysWithValues: previousRecordTypes.map {
          ($0.tableName, $0)
        }
      )
      let currentRecordTypeByTableName = Dictionary(
        uniqueKeysWithValues: currentRecordTypes.map {
          ($0.tableName, $0)
        }
      )
      try uploadRecordsToCloudKit(
        previousRecordTypeByTableName: previousRecordTypeByTableName,
        currentRecordTypeByTableName: currentRecordTypeByTableName
      )
      return Task {
        await withErrorReporting(.sqliteDataCloudKitFailure) {
          try await fetchChangesFromSchemaChange(
            previousRecordTypeByTableName: previousRecordTypeByTableName,
            currentRecordTypeByTableName: currentRecordTypeByTableName
          )
        }
      }
    }

    private func cacheUserTables(recordTypes: [RecordType]) {
      withErrorReporting(.sqliteDataCloudKitFailure) {
        try userDatabase.write { db in
          try RecordType
            .upsert { recordTypes.map { RecordType.Draft($0) } }
            .execute(db)
        }
      }
    }

    private func uploadRecordsToCloudKit(
      previousRecordTypeByTableName: [String: RecordType],
      currentRecordTypeByTableName: [String: RecordType]
    ) throws {
      let newTableNames = currentRecordTypeByTableName.keys.filter { tableName in
        previousRecordTypeByTableName[tableName] == nil
      }

      try userDatabase.write { db in
        try Self.$_isUpdatingRecord.withValue(false) {
          for tableName in newTableNames {
            guard let table = tablesByName[tableName]
            else { continue }

            let parentForeignKey =
              foreignKeysByTableName[tableName]?.count == 1
              ? foreignKeysByTableName[tableName]?.first
              : nil

            func open<T: PrimaryKeyedTable<UUID>>(_: T.Type) throws {
              withErrorReporting(.sqliteDataCloudKitFailure) {
                try SyncMetadata.insert { columns in
                  (
                    columns.recordType,
                    columns.recordName,
                    columns.parentRecordName
                  )
                } select: {
                  T.select { columns in
                    (
                      SQLQueryExpression("\(quote: T.tableName, delimiter: .text)"),
                      SQLQueryExpression(
                        """
                        \(columns.primaryKey) || ':' || \(quote: T.tableName, delimiter: .text)
                        """,
                        as: SyncMetadata.RecordName.self
                      ),
                      parentForeignKey.map { parentForeignKey in
                        SQLQueryExpression(
                          """
                          \(T.self).\(quote: parentForeignKey.from, delimiter: .identifier) \
                          || ':' || \(quote: parentForeignKey.table, delimiter: .text) 
                          """,
                          as: SyncMetadata.RecordName?.self
                        )
                      }
                        ?? SQLQueryExpression("NULL")
                    )
                  }
                }
                .execute(db)
              }
            }
            try open(table)
          }
        }
      }
    }

    private func fetchChangesFromSchemaChange(
      previousRecordTypeByTableName: [String: RecordType],
      currentRecordTypeByTableName: [String: RecordType]
    ) async throws {

      let tablesWithChangedSchemas = currentRecordTypeByTableName.filter { tableName, recordType in
        previousRecordTypeByTableName[tableName]?.schema != recordType.schema
      }

      for (tableName, recordType) in tablesWithChangedSchemas {
        guard let table = tablesByName[tableName]
        else { continue }
        func open<T: PrimaryKeyedTable<UUID>>(_: T.Type) async throws {
          let previousRecordType = previousRecordTypeByTableName[tableName]
          let changedColumns =
            [T.columns.primaryKey.name]
            + recordType.tableInfo.subtracting(previousRecordType?.tableInfo ?? [])
            .map(\.name)
          let lastKnownServerRecords = try await metadatabase.read { db in
            try SyncMetadata
              .where { $0.recordType.eq(tableName) }
              .select(\._lastKnownServerRecordAllFields)
              .fetchAll(db)
              .compactMap(\.self)
          }
          for lastKnownServerRecord in lastKnownServerRecords {
            let query = update(T.self, record: lastKnownServerRecord, columnNames: changedColumns)
            try await userDatabase.write { db in
              try SQLQueryExpression(query).execute(db)
            }
          }
        }
        try await open(table)
      }
    }

    package func tearDownSyncEngine() async throws {
      let syncEngines = syncEngines.withValue(\.self)
      async let privateCancellation: Void? = syncEngines.private?.cancelOperations()
      async let sharedCancellation: Void? = syncEngines.shared?.cancelOperations()

      try await userDatabase.write { db in
        for (childTableName, foreignKeys) in self.foreignKeysByTableName {
          for foreignKey in foreignKeys {
            try foreignKey.dropTriggers(for: childTableName, db: db)
          }
        }
        for table in self.tables {
          try table.dropTriggers(db: db)
        }
        for trigger in SyncMetadata.callbackTriggers.reversed() {
          try trigger.drop().execute(db)
        }
        db.remove(function: .didDelete(syncEngine: self))
        db.remove(function: .didUpdate(syncEngine: self))
        db.remove(function: .syncEngineIsUpdatingRecord)
        db.remove(function: .datetime)
      }
      try await userDatabase.write { db in
        // TODO: Do an `.erase()` + re-migrate
        try SyncMetadata.delete().execute(db)
        try RecordType.delete().execute(db)
        try StateSerialization.delete().execute(db)
      }
      _ = await (privateCancellation, sharedCancellation)
    }

    func deleteLocalData() async throws {
      try await tearDownSyncEngine()
      withErrorReporting(.sqliteDataCloudKitFailure) {
        try userDatabase.write { db in
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
      print("didDelete", recordName)
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

    package func acceptShare(metadata: ShareMetadata) async throws {
      guard let metadata = metadata.rawValue
      else {
        reportIssue("TODO")
        return
      }
      guard let rootRecordID = metadata.hierarchicalRootRecordID
      else {
        reportIssue("TODO")
        return
      }
      let container = type(of: container).createContainer(identifier: metadata.containerIdentifier)
      // TODO: do something with the CKShare returned? save it in SyncMetadata?
      _ = try await container.accept(metadata)
      try await syncEngines.shared?.fetchChanges(
        .init(
          scope: .zoneIDs([rootRecordID.zoneID]),
          operationGroup: nil
        )
      )
    }

    public static func isUpdatingRecord() -> SQLQueryExpression<Bool> {
      SQLQueryExpression("\(raw: DatabaseFunction.syncEngineIsUpdatingRecord.name)()")
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
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    fileprivate static func dropTriggers(db: Database) throws {
      for trigger in metadataTriggers(parentForeignKey: nil).reversed() {
        try trigger.drop().execute(db)
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncEngine: CKSyncEngineDelegate, SyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
      guard let event = Event(event)
      else {
        reportIssue("Unrecognized event received: \(event)")
        return
      }
      await handleEvent(event, syncEngine: syncEngine)
    }

    package func handleEvent(_ event: Event, syncEngine: any SyncEngineProtocol) async {
      logger.log(event, syncEngine: syncEngine)

      switch event {
      case .accountChange(let changeType):
        await handleAccountChange(changeType: changeType, syncEngine: syncEngine)
      case .stateUpdate(let stateSerialization):
        handleStateUpdate(stateSerialization: stateSerialization, syncEngine: syncEngine)
      case .fetchedDatabaseChanges(let modifications, let deletions):
        handleFetchedDatabaseChanges(
          modifications: modifications,
          deletions: deletions,
          syncEngine: syncEngine
        )
      case .sentDatabaseChanges:
        break
      case .fetchedRecordZoneChanges(let modifications, let deletions):
        await handleFetchedRecordZoneChanges(
          modifications: modifications,
          deletions: deletions,
          syncEngine: syncEngine
        )
      case .sentRecordZoneChanges(
        let savedRecords,
        let failedRecordSaves,
        let deletedRecordIDs,
        let failedRecordDeletes
      ):
        await handleSentRecordZoneChanges(
          savedRecords: savedRecords,
          failedRecordSaves: failedRecordSaves,
          deletedRecordIDs: deletedRecordIDs,
          failedRecordDeletes: failedRecordDeletes,
          syncEngine: syncEngine
        )
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
      await nextRecordZoneChangeBatch(
        reason: context.reason,
        options: context.options,
        syncEngine: syncEngine
      )
    }

    package func nextRecordZoneChangeBatch(
      reason: CKSyncEngine.SyncReason = .scheduled,
      options: CKSyncEngine.SendChangesOptions = CKSyncEngine.SendChangesOptions(scope: .all),
      syncEngine: any SyncEngineProtocol
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
      let allChanges = syncEngine.state.pendingRecordZoneChanges.filter(options.scope.contains)
      guard !allChanges.isEmpty
      else { return nil }

      let changes = allChanges.sorted { lhs, rhs in
        switch (lhs, rhs) {
        case (.saveRecord(let lhs), .saveRecord(let rhs)):
          guard
            let lhsRecordName = SyncMetadata.RecordName(rawValue: lhs.recordName),
            let lhsIndex = tablesByOrder[lhsRecordName.recordType],
            let rhsRecordName = SyncMetadata.RecordName(rawValue: rhs.recordName),
            let rhsIndex = tablesByOrder[rhsRecordName.recordType]
          else { return true }
          return lhsIndex < rhsIndex
        case (.deleteRecord(let lhs), .deleteRecord(let rhs)):
          guard
            let lhsRecordName = SyncMetadata.RecordName(rawValue: lhs.recordName),
            let lhsIndex = tablesByOrder[lhsRecordName.recordType],
            let rhsRecordName = SyncMetadata.RecordName(rawValue: rhs.recordName),
            let rhsIndex = tablesByOrder[rhsRecordName.recordType]
          else { return true }
          return lhsIndex > rhsIndex
        case (.saveRecord, .deleteRecord):
          return false
        case (.deleteRecord, .saveRecord):
          return true
        default:
          return true
        }
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
            [\(syncEngine.database.databaseScope.label)] nextRecordZoneChangeBatch: \(reason)
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
          let (metadata, allFields) = await withErrorReporting(
            .sqliteDataCloudKitFailure,
            catching: {
              try await metadatabase.read { db in
                try SyncMetadata
                  .find(recordName)
                  .select { ($0, $0._lastKnownServerRecordAllFields) }
                  .fetchOne(db)
              }
            }
          )
            ?? nil
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
              try userDatabase.read { db in
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
            allFields
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
          await refreshLastKnownServerRecord(record)
          sentRecord = recordID
          return record
        }
        return await open(table)
      }
      return batch
    }

    package func handleAccountChange(
      changeType: CKSyncEngine.Event.AccountChange.ChangeType,
      syncEngine: any SyncEngineProtocol
    ) async {
      switch changeType {
      case .signIn:
        syncEngines.withValue {
          $0.private?.state.add(pendingDatabaseChanges: [.saveZone(Self.defaultZone)])
        }
        for table in tables {
          withErrorReporting(.sqliteDataCloudKitFailure) {
            let recordNames = try userDatabase.read { db in
              func open<T: PrimaryKeyedTable<UUID>>(_: T.Type) throws -> [SyncMetadata.RecordName] {
                try T
                  .select(\.primaryKey)
                  .fetchAll(db)
                  .map { T.recordName(for: $0) }
              }
              return try open(table)
            }
            syncEngine.state.add(
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
      case .signOut, .switchAccounts:
        await withErrorReporting(.sqliteDataCloudKitFailure) {
          try await deleteLocalData()
        }
      @unknown default:
        break
      }
    }

    package func handleStateUpdate(
      stateSerialization: CKSyncEngine.State.Serialization,
      syncEngine: any SyncEngineProtocol
    ) {
      withErrorReporting(.sqliteDataCloudKitFailure) {
        try userDatabase.write { db in
          try StateSerialization.upsert {
            StateSerialization.Draft(
              scope: syncEngine.database.databaseScope,
              data: stateSerialization
            )
          }
          .execute(db)
        }
      }
    }

    package func handleFetchedDatabaseChanges(
      modifications: [CKRecordZone.ID],
      deletions: [(zoneID: CKRecordZone.ID, reason: CKDatabase.DatabaseChange.Deletion.Reason)],
      syncEngine: any SyncEngineProtocol
    ) {
      // TODO: How to handle this?
      withErrorReporting(.sqliteDataCloudKitFailure) {
        try userDatabase.write { db in
          for deletion in deletions {
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
        _ = modifications
      }
    }

    package func handleFetchedRecordZoneChanges(
      modifications: [CKRecord] = [],
      deletions: [(recordID: CKRecord.ID, recordType: CKRecord.RecordType)] = [],
      syncEngine: any SyncEngineProtocol
    ) async {
      let shares: [CKShare] = []
      for record in modifications {
        if let share = record as? CKShare {
          await withErrorReporting {
            try await cacheShare(share)
          }
        } else {
          upsertFromServerRecord(record)
        }
        if let shareReference = record.share,
          // TODO: do this in parallel to not hold everything up? i think this is the cause of records staggering in
          let shareRecord = try? await syncEngine.database.record(for: shareReference.recordID),
          let share = shareRecord as? CKShare
        {
          await withErrorReporting {
            try await cacheShare(share)
          }
        }
      }

      // TODO: Group by recordType and delete in batches
      for (recordID, recordType) in deletions {
        if let table = tablesByName[recordType] {
          guard let recordName = SyncMetadata.RecordName(recordID: recordID)
          else {
            continue
          }
          func open<T: PrimaryKeyedTable<UUID>>(_: T.Type) {
            withErrorReporting(.sqliteDataCloudKitFailure) {
              try userDatabase.write { db in
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

    package func handleSentRecordZoneChanges(
      savedRecords: [CKRecord] = [],
      failedRecordSaves: [(record: CKRecord, error: CKError)] = [],
      deletedRecordIDs: [CKRecord.ID] = [],
      failedRecordDeletes: [CKRecord.ID: CKError] = [:],
      syncEngine: any SyncEngineProtocol
    ) async {
      for savedRecord in savedRecords {
        await refreshLastKnownServerRecord(savedRecord)
      }

      var newPendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] = []
      var newPendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
      defer {
        syncEngine.state.add(pendingDatabaseChanges: newPendingDatabaseChanges)
        syncEngine.state.add(pendingRecordZoneChanges: newPendingRecordZoneChanges)
      }
      for failedRecordSave in failedRecordSaves {
        let failedRecord = failedRecordSave.record
        guard let recordName = SyncMetadata.RecordName(rawValue: failedRecord.recordID.recordName)
        else {
          continue
        }

        func clearServerRecord() {
          withErrorReporting {
            try userDatabase.write { db in
              try SyncMetadata
                .find(recordName)
                .update { $0.setLastKnownServerRecord(nil) }
                .execute(db)
            }
          }
        }

        switch failedRecordSave.error.code {
        case .serverRecordChanged:
          guard let serverRecord = failedRecordSave.error.serverRecord else { continue }
          upsertFromServerRecord(serverRecord)
          newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))

        case .zoneNotFound:
          let zone = CKRecordZone(zoneID: failedRecord.recordID.zoneID)
          newPendingDatabaseChanges.append(.saveZone(zone))
          newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
          clearServerRecord()

        case .unknownItem:
          newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
          clearServerRecord()

        case .serverRejectedRequest:
          clearServerRecord()

        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
          .notAuthenticated, .referenceViolation, .operationCancelled, .batchRequestFailed,
          .internalError, .partialFailure, .badContainer, .requestRateLimited, .missingEntitlement,
          .permissionFailure, .invalidArguments, .resultsTruncated, .assetFileNotFound,
          .assetFileModified, .incompatibleVersion, .constraintViolation, .changeTokenExpired,
          .badDatabase, .quotaExceeded, .limitExceeded, .userDeletedZone, .tooManyParticipants,
          .alreadyShared, .managedAccountRestricted, .participantMayNeedVerification,
          .serverResponseLost, .assetNotAvailable, .accountTemporarilyUnavailable:
          continue
        @unknown default:
          continue
        }
      }
      // TODO: handle event.failedRecordDeletes ? look at apple sample code

      if !failedRecordDeletes.isEmpty {
        print("!!!!")
      }
    }

    private func cacheShare(_ share: CKShare) async throws {
      guard let url = share.url
      else { return }

      guard
        let metadata = try? await container.shareMetadata(
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
        return
      }

      try await userDatabase.write { db in
        try SyncMetadata
          .find(recordName)
          .update { $0.share = share }
          .execute(db)
      }
    }

    private func deleteShare(recordID: CKRecord.ID, recordType: String) throws {
      // TODO: more efficient way to do this?
      try userDatabase.write { db in
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

    private func upsertFromServerRecord(_ serverRecord: CKRecord) {
      withErrorReporting(.sqliteDataCloudKitFailure) {
        guard let table = tablesByName[serverRecord.recordType]
        else {
          // TODO: Should we be reporting this?
          // What if another device makes changes to a table this device doesn't know about?
          reportIssue(
            .sqliteDataCloudKitFailure.appending(
              """
              : No table to merge from: "\(serverRecord.recordType)"
              """
            )
          )
          return
        }
        guard let recordName = SyncMetadata.RecordName(recordID: serverRecord.recordID)
        else { return }

        let result = try metadatabase.read { db in
          try SyncMetadata
            .find(recordName)
            .select { ($0, $0._lastKnownServerRecordAllFields) }
            .fetchOne(db)
        }
        let metadata = result?.0
        let allFields = result?.1
        serverRecord.userModificationDate =
          metadata?.userModificationDate ?? serverRecord.userModificationDate

        func open<T: PrimaryKeyedTable<UUID>>(_: T.Type) throws {
          var columnNames = T.TableColumns.allColumns.map(\.name)
          if let allFields {
            let row = try userDatabase.read { db in
              try T.find(recordName.id).fetchOne(db)
            }
            guard let row
            else {
              reportIssue("Local database record could not be found for '\(recordName.rawValue)'.")
              return
            }
            serverRecord.update(
              with: allFields,
              row: T(queryOutput: row),
              columnNames: &columnNames
            )
          }

          // TODO: Append more ON CONFLICT clauses for each unique constraint?
          // TODO: Use WHERE to scope the update?
          try userDatabase.write { db in
            let query = upsert(T.self, record: serverRecord, columnNames: columnNames)
            try SQLQueryExpression(query).execute(db)
            try SyncMetadata
              .find(recordName)
              .update { $0.setLastKnownServerRecord(serverRecord) }
              .execute(db)
          }
        }
        try open(table)
      }
    }

    private func refreshLastKnownServerRecord(_ record: CKRecord) async {
      guard let recordName = SyncMetadata.RecordName(recordID: record.recordID)
      else {
        return
      }
      let metadata = await metadataFor(recordName: recordName)

      func updateLastKnownServerRecord() {
        withErrorReporting(.sqliteDataCloudKitFailure) {
          try userDatabase.write { db in
            try SyncMetadata
              .find(recordName)
              .update { $0.setLastKnownServerRecord(record) }
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

    private func metadataFor(recordName: SyncMetadata.RecordName) async -> SyncMetadata? {
      await withErrorReporting(.sqliteDataCloudKitFailure) {
        try await metadatabase.read { db in
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

    fileprivate static var syncEngineIsUpdatingRecord: Self {
      Self(.sqliteDataCloudKitSchemaName + "_" + "syncEngineIsUpdatingRecord", argumentCount: 0) {
        _ in
        SyncEngine._isUpdatingRecord
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

  extension String {
    package static let sqliteDataCloudKitSchemaName = "sqlitedata_icloud"
    fileprivate static let sqliteDataCloudKitFailure = "SharingGRDB CloudKit Failure"
  }

  @available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
  extension URL {
    package static func metadatabase(containerIdentifier: String?) throws -> Self {
      @Dependency(\.context) var context
      let base: URL
      if context == .live {
        try FileManager.default.createDirectory(
          at: .applicationSupportDirectory,
          withIntermediateDirectories: true
        )
        base = .applicationSupportDirectory
      } else {
        base = .temporaryDirectory
      }
      return base.appending(
        component: "\(containerIdentifier.map { "\($0)." } ?? "")sqlite-data-icloud.sqlite"
      )
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  package struct SyncEngines {
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
    package var `private`: (any SyncEngineProtocol)? {
      guard let _private
      else {
        reportIssue("Private sync engine has not been set.")
        return nil
      }
      return _private
    }
    package var `shared`: (any SyncEngineProtocol)? {
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

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private func validateSchema(
    tables: [any PrimaryKeyedTable.Type],
    userDatabase: UserDatabase
  ) throws {
    let tableNames = Set(tables.map { $0.tableName })
    try userDatabase.read { db in
      let triggers = try SQLQueryExpression(
        """
        SELECT "name", "tbl_name", "sql"
          FROM "sqlite_master"
          WHERE "type" = 'trigger'
        UNION
        SELECT "name", "tbl_name", "sql"
          FROM "sqlite_temp_master"
          WHERE "type" = 'trigger'
        """,
        as: (String, String, String).self
      )
      .fetchAll(db)
      .filter { _, tableName, _ in tableNames.contains(tableName) }
      let invalidTriggers = triggers.compactMap { name, _, sql in
        let isValid =
          sql
          .lowercased()
          .contains("\(DatabaseFunction.syncEngineIsUpdatingRecord.name)()".lowercased())
        return isValid ? nil : name
      }
      guard invalidTriggers.isEmpty
      else {
        throw InvalidUserTriggers(triggers: invalidTriggers)
      }

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

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public struct InvalidUserTriggers: LocalizedError {
    let triggers: [String]
    public var localizedDescription: String {
      """
      Triggers must include 'WHEN NOT \(DatabaseFunction.syncEngineIsUpdatingRecord.name)()' \
      clause: \(triggers.map { "'\($0)'" }.joined(separator: ", "))
      """
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
    init(_ type: any PrimaryKeyedTable<UUID>.Type) {
      self.type = type
    }
    func hash(into hasher: inout Hasher) {
      hasher.combine(ObjectIdentifier(type))
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.type == rhs.type
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private func tablesByOrder(
    userDatabase: UserDatabase,
    tables: [any PrimaryKeyedTable<UUID>.Type],
    tablesByName: [String: any PrimaryKeyedTable<UUID>.Type]
  ) throws -> [String: Int] {
    let tableDependencies = try userDatabase.read { db in
      var dependencies: [HashablePrimaryKeyedTableType: [any PrimaryKeyedTable<UUID>.Type]] = [:]
      for table in tables {
        let toTables = try SQLQueryExpression(
          """
          SELECT "table" FROM pragma_foreign_key_list(\(quote: table.tableName, delimiter: .text))
          """,
          as: String.self
        )
        .fetchAll(db)
        for toTable in toTables {
          guard let toTableType = tablesByName[toTable]
          else { continue }
          dependencies[HashablePrimaryKeyedTableType(table), default: []].append(toTableType)
        }
      }
      return dependencies
    }

    var visited = Set<HashablePrimaryKeyedTableType>()
    var marked = Set<HashablePrimaryKeyedTableType>()
    var result: [String: Int] = [:]
    for table in tableDependencies.keys {
      try visit(table: table)
    }
    return result

    func visit(table: HashablePrimaryKeyedTableType) throws {
      guard !visited.contains(table)
      else { return }
      guard !marked.contains(table)
      else {
        // TODO: Can possibly allow cycles by assigning all elements in the cycle the same level and forcing "DELETE CASCADE" on the relationships.
        struct CycleError: Error {}
        throw CycleError()
      }

      marked.insert(table)
      for dependency in tableDependencies[table] ?? [] {
        try visit(table: HashablePrimaryKeyedTableType(dependency))
      }
      marked.remove(table)
      visited.insert(table)
      result[table.type.tableName] = result.count
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension Updates<SyncMetadata> {
    mutating func setLastKnownServerRecord(_ lastKnownServerRecord: CKRecord?) {
      self.lastKnownServerRecord = lastKnownServerRecord
      self._lastKnownServerRecordAllFields = lastKnownServerRecord
      if let lastKnownServerRecord {
        self.userModificationDate = lastKnownServerRecord.userModificationDate
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private func upsert<T: PrimaryKeyedTable<UUID>>(
    _: T.Type,
    record: CKRecord,
    columnNames: some Collection<String>
  ) -> QueryFragment {
    guard
      columnNames.contains(where: { $0 != T.columns.primaryKey.name })
    else {
      return ""
    }
    var query: QueryFragment = "INSERT INTO \(T.self) ("
    query.append(columnNames.map { "\(quote: $0)" }.joined(separator: ", "))
    query.append(") VALUES (")
    query.append(
      columnNames
        .map { columnName in
          if let asset = record[columnName] as? CKAsset {
            @Dependency(\.dataManager) var dataManager
            return (try? asset.fileURL.map { try dataManager.load($0) })?
              .queryFragment ?? "NULL"
          } else {
            return record.encryptedValues[columnName]?.queryFragment ?? "NULL"
          }
        }
        .joined(separator: ", ")
    )
    query.append(") ON CONFLICT(\(quote: T.columns.primaryKey.name)) DO UPDATE SET ")
    query.append(
      columnNames
        .filter { columnName in columnName != T.columns.primaryKey.name }
        .map {
          """
          \(quote: $0) = "excluded".\(quote: $0)
          """
        }
        .joined(separator: ",")
    )
    return query
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private func update<T: PrimaryKeyedTable<UUID>>(
    _: T.Type,
    record: CKRecord,
    columnNames: some Collection<String>
  ) -> QueryFragment {
    let nonPrimaryKeyColumns = columnNames.filter { $0 != T.columns.primaryKey.name }
    guard
      !nonPrimaryKeyColumns.isEmpty,
      let id = record.encryptedValues[T.columns.primaryKey.name] as? String
    else {
      return ""
    }
    var query: QueryFragment = "UPDATE \(T.self) SET "
    query.append(
      columnNames
        .filter { columnName in columnName != T.columns.primaryKey.name }
        .map { columnName in
          if let asset = record[columnName] as? CKAsset {
            @Dependency(\.dataManager) var dataManager
            let data = try? asset.fileURL.map { try dataManager.load($0) }
            if data == nil {
              // TODO: Handle assets that need to be re-downloaded
              reportIssue("Asset data not found on disk")
            }
            return """
              \(quote: columnName) = \(data?.queryFragment ?? "NULL")
              """
          } else {
            return """
              \(quote: columnName) = \(record.encryptedValues[columnName]?.queryFragment ?? "NULL") 
              """
          }
        }
        .joined(separator: ",")
    )
    query.append(" WHERE \(T.columns.primaryKey) = \(bind: id)")
    return query
  }
#endif
