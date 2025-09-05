#if canImport(CloudKit)
  import CloudKit
  import ConcurrencyExtras
  import CustomDump
  import Dependencies
  import GRDB
  import OrderedCollections
  import OSLog
  import Observation
  import StructuredQueriesCore
  import SwiftData

  /// An object that manages the synchronization of local and remote SQLite data.
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public final class SyncEngine: Observable, Sendable {
    package let userDatabase: UserDatabase
    package let logger: Logger
    package let metadatabase: any DatabaseWriter
    package let tables: [any PrimaryKeyedTable.Type]
    package let privateTables: [any PrimaryKeyedTable.Type]
    let tablesByName: [String: any PrimaryKeyedTable.Type]
    private let tablesByOrder: [String: Int]
    let foreignKeysByTableName: [String: [ForeignKey]]
    package let syncEngines = LockIsolated<SyncEngines>(SyncEngines())
    package let defaultZone: CKRecordZone
    let defaultSyncEngines:
      @Sendable (any DatabaseReader, SyncEngine)
        -> (private: any SyncEngineProtocol, shared: any SyncEngineProtocol)
    package let container: any CloudContainer
    let dataManager = Dependency(\.dataManager)
    private let observationRegistrar = ObservationRegistrar()

    /// The error message used when a write occurs to a record for which the current user
    /// does not have permission.
    ///
    /// This error is thrown from any database write to a row for which the current user does
    /// not have permissions to write, as determined by its `CKShare` (if applicable). To catch
    /// this error try casting it to `DatabaseError` and checking its message:
    ///
    /// ```swift
    /// do {
    ///   try await database.write { db in
    ///     Reminder.find(id)
    ///       .update { $0.title = "Personal" }
    ///       .execute(db)
    ///   }
    /// } catch let error as DatabaseError where error.message == SyncEngine.writePermissionError {
    ///   // User does not have permission to write to this record.
    /// }
    /// ```
    public static let writePermissionError =
      "co.pointfree.SQLiteData.CloudKit.write-permission-error"
    public static let invalidRecordNameError =
      "co.pointfree.SQLiteData.CloudKit.invalid-record-name-error"

    /// Initialize a sync engine.
    ///
    /// - Parameters:
    ///   - database: The database to synchronize to CloudKit.
    ///   - tables: A list of tables that you want to synchronize _and_ that you want to be
    ///   shareable with other users on CloudKit.
    ///   - privateTables: A list of tables that you want to synchronize to CloudKit but that
    ///   you do not want to be shareable with other users.
    ///   - containerIdentifier: The container identifier in CloudKit to synchronize to. If omitted
    ///   the container will be determined from the entitlements of your app.
    ///   - defaultZone: The zone for all records to be stored in.
    ///   - startImmediately: Determines if the sync engine starts right away or requires an
    ///   explicit call to ``stop()``. By default this argument is `true`.
    ///   - logger: The logger used to log events in the sync engine. By default a `.disabled`
    ///   logger is used, which means logs are not printed.
    public convenience init<each T1: PrimaryKeyedTable, each T2: PrimaryKeyedTable>(
      for database: any DatabaseWriter,
      tables: repeat (each T1).Type,
      privateTables: repeat (each T2).Type,
      containerIdentifier: String? = nil,
      defaultZone: CKRecordZone = CKRecordZone(zoneName: "co.pointfree.SQLiteData.defaultZone"),
      startImmediately: Bool = !isTesting,
      logger: Logger = isTesting
        ? Logger(.disabled) : Logger(subsystem: "SQLiteData", category: "CloudKit")
    ) throws
    where
      repeat (each T1).PrimaryKey.QueryOutput: IdentifierStringConvertible,
      repeat (each T2).PrimaryKey.QueryOutput: IdentifierStringConvertible
    {
      let containerIdentifier =
        containerIdentifier
        ?? ModelConfiguration(groupContainer: .automatic).cloudKitContainerIdentifier

      var allTables: [any PrimaryKeyedTable.Type] = []
      var allPrivateTables: [any PrimaryKeyedTable.Type] = []
      for table in repeat each tables {
        allTables.append(table)
      }
      for privateTable in repeat each privateTables {
        allPrivateTables.append(privateTable)
      }
      let userDatabase = UserDatabase(database: database)

      guard !isTesting
      else {
        let privateDatabase = MockCloudDatabase(databaseScope: .private)
        let sharedDatabase = MockCloudDatabase(databaseScope: .shared)
        try self.init(
          container: MockCloudContainer(
            containerIdentifier: containerIdentifier ?? "iCloud.co.pointfree.SQLiteData.Tests",
            privateCloudDatabase: privateDatabase,
            sharedCloudDatabase: sharedDatabase
          ),
          defaultZone: defaultZone,
          defaultSyncEngines: { _, syncEngine in
            (
              private: MockSyncEngine(
                database: privateDatabase,
                delegate: syncEngine,
                state: MockSyncEngineState()
              ),
              shared: MockSyncEngine(
                database: sharedDatabase,
                delegate: syncEngine,
                state: MockSyncEngineState()
              )
            )
          },
          userDatabase: userDatabase,
          logger: logger,
          tables: allTables,
          privateTables: allPrivateTables
        )
        try setUpSyncEngine()
        if startImmediately {
          _ = try start()
        }
        return
      }

      guard let containerIdentifier else {
        throw SchemaError(
          reason: .noCloudKitContainer,
          debugDescription: """
            No default CloudKit container found. Please add a container identifier to your app's \
            entitlements.
            """
        )
      }

      let container = CKContainer(identifier: containerIdentifier)
      try self.init(
        container: container,
        defaultZone: defaultZone,
        defaultSyncEngines: { metadatabase, syncEngine in
          (
            private: CKSyncEngine(
              CKSyncEngine.Configuration(
                database: container.privateCloudDatabase,
                stateSerialization: try? metadatabase.read { db in
                  try StateSerialization
                    .find(#bind(.private))
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
                    .find(#bind(.shared))
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
        tables: allTables,
        privateTables: allPrivateTables
      )
      try setUpSyncEngine()
      if startImmediately {
        _ = try start()
      }
    }

    package init(
      container: any CloudContainer,
      defaultZone: CKRecordZone,
      defaultSyncEngines:
        @escaping @Sendable (
          any DatabaseReader,
          SyncEngine
        ) -> (private: any SyncEngineProtocol, shared: any SyncEngineProtocol),
      userDatabase: UserDatabase,
      logger: Logger,
      tables: [any PrimaryKeyedTable.Type],
      privateTables: [any PrimaryKeyedTable.Type] = []
    ) throws {
      let allTables = Set((tables + privateTables).map(HashablePrimaryKeyedTableType.init))
        .map(\.type)
      self.tables = allTables
      self.privateTables = privateTables

      let foreignKeysByTableName = Dictionary(
        uniqueKeysWithValues: try userDatabase.read { db in
          try allTables.map { table -> (String, [ForeignKey]) in
            (
              table.tableName,
              try ForeignKey.all(table.tableName).fetchAll(db)
            )
          }
        }
      )
      self.container = container
      self.defaultZone = defaultZone
      self.defaultSyncEngines = defaultSyncEngines
      self.userDatabase = userDatabase
      self.logger = logger
      self.metadatabase = try defaultMetadatabase(
        logger: logger,
        url: try URL.metadatabase(
          databasePath: userDatabase.path,
          containerIdentifier: container.containerIdentifier
        )
      )
      self.tablesByName = Dictionary(uniqueKeysWithValues: self.tables.map { ($0.tableName, $0) })
      self.foreignKeysByTableName = foreignKeysByTableName
      tablesByOrder = try SQLiteData.tablesByOrder(
        userDatabase: userDatabase,
        tables: allTables,
        tablesByName: tablesByName
      )
      try validateSchema()
    }

    @TaskLocal package static var _isSynchronizingChanges = false

    nonisolated package func setUpSyncEngine() throws {
      let migrator = metadatabaseMigrator()
      #if DEBUG
        try metadatabase.read { db in
          let hasSchemaChanges = try migrator.hasSchemaChanges(db)
          assert(!hasSchemaChanges, "Metadatabase migrations must not be modified after release")
        }
      #endif
      try migrator.migrate(metadatabase)

      try userDatabase.write { db in
        let attachedMetadatabasePath: String? =
          try #sql(
            """
            SELECT "file"
            FROM pragma_database_list()
            WHERE "name" = \(bind: String.sqliteDataCloudKitSchemaName)
            """,
            as: String.self
          )
          .fetchOne(db)
        if let attachedMetadatabasePath {
          let attachedMetadatabaseName = URL(filePath: metadatabase.path).lastPathComponent
          let metadatabaseName = URL(filePath: attachedMetadatabasePath).lastPathComponent
          if attachedMetadatabaseName != metadatabaseName {
            throw SchemaError(
              reason: .metadatabaseMismatch(
                attachedPath: attachedMetadatabasePath,
                syncEngineConfiguredPath: metadatabase.path
              ),
              debugDescription: """
                Metadatabase attached in 'prepareDatabase' does not match metadatabase prepared in \
                'SyncEngine.init'. Are different CloudKit container identifiers being provided?
                """
            )
          }

        } else {
          try #sql(
            """
            ATTACH DATABASE \(bind: metadatabase.path) AS \(quote: .sqliteDataCloudKitSchemaName)
            """
          )
          .execute(db)
        }
        db.add(function: $datetime)
        db.add(function: $syncEngineIsSynchronizingChanges)
        db.add(function: $didUpdate)
        db.add(function: $didDelete)
        db.add(function: $hasPermission)

        for trigger in SyncMetadata.callbackTriggers(for: self) {
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
    }

    /// Starts the sync engine if it is stopped.
    ///
    /// When a sync engine is started it will upload all data stored locally that has not yet
    /// been synchronized to CloudKit, and will download all changes from CloudKit since the
    /// last time it synchronized.
    ///
    /// > Note: By default, sync engines start syncing when initialized.
    public func start() async throws {
      try await start().value
    }

    /// Stops the sync engine if it is running.
    ///
    /// All edits made after stopping the sync engine will not be synchronized to CloudKit.
    /// You must start the sync engine again using ``start()`` to synchronize the changes.
    public func stop() {
      guard isRunning else { return }
      observationRegistrar.withMutation(of: self, keyPath: \.isRunning) {
        syncEngines.withValue {
          $0 = SyncEngines()
        }
      }
    }

    /// Determines if the sync engine is currently running or not.
    public var isRunning: Bool {
      observationRegistrar.access(self, keyPath: \.isRunning)
      return syncEngines.withValue {
        $0.isRunning
      }
    }

    private func start() throws -> Task<Void, Never> {
      guard !isRunning else { return Task {} }
      let (privateSyncEngine, sharedSyncEngine) = defaultSyncEngines(metadatabase, self)
      observationRegistrar.withMutation(of: self, keyPath: \.isRunning) {
        syncEngines.withValue {
          $0 = SyncEngines(
            private: privateSyncEngine,
            shared: sharedSyncEngine
          )
        }
      }

      let previousRecordTypes = try metadatabase.read { db in
        try RecordType.all.fetchAll(db)
      }
      let currentRecordTypes = try userDatabase.read { db in
        let namesAndSchemas =
          try SQLiteSchema
          .where {
            $0.type.eq(#bind(.table))
              && $0.tableName.in(tables.map { $0.tableName })
          }
          .fetchAll(db)
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
      return Task {
        await withErrorReporting(.sqliteDataCloudKitFailure) {
          guard try await container.accountStatus() == .available
          else { return }
          try await uploadRecordsToCloudKit(
            previousRecordTypeByTableName: previousRecordTypeByTableName,
            currentRecordTypeByTableName: currentRecordTypeByTableName
          )
          try await updateLocalFromSchemaChange(
            previousRecordTypeByTableName: previousRecordTypeByTableName,
            currentRecordTypeByTableName: currentRecordTypeByTableName
          )
          try await cacheUserTables(recordTypes: currentRecordTypes)
        }
      }
    }

    private func cacheUserTables(recordTypes: [RecordType]) async throws {
      try await userDatabase.write { db in
        try RecordType
          .upsert { recordTypes.map { RecordType.Draft($0) } }
          .execute(db)
      }
    }

    private func uploadRecordsToCloudKit(
      previousRecordTypeByTableName: [String: RecordType],
      currentRecordTypeByTableName: [String: RecordType]
    ) async throws {
      let pendingRecordZoneChanges = try await metadatabase.read { db in
        try PendingRecordZoneChange
          .select(\.pendingRecordZoneChange)
          .fetchAll(db)
      }
      let changesByIsPrivate = Dictionary(grouping: pendingRecordZoneChanges) {
        switch $0 {
        case .deleteRecord(let recordID), .saveRecord(let recordID):
          recordID.zoneID.ownerName == CKCurrentUserDefaultName
        @unknown default:
          false
        }
      }
      syncEngines.withValue {
        $0.private?.state.add(pendingRecordZoneChanges: changesByIsPrivate[true] ?? [])
        $0.shared?.state.add(pendingRecordZoneChanges: changesByIsPrivate[false] ?? [])
      }

      try await userDatabase.write { db in
        try PendingRecordZoneChange.delete().execute(db)
      }

      let newTableNames = currentRecordTypeByTableName.keys.filter { tableName in
        previousRecordTypeByTableName[tableName] == nil
      }

      try await userDatabase.write { db in
        try Self.$_isSynchronizingChanges.withValue(false) {
          for tableName in newTableNames {
            try self.uploadRecordsToCloudKit(tableName: tableName, db: db)
          }
        }
      }
    }

    private func uploadRecordsToCloudKit<T: PrimaryKeyedTable>(table: T.Type, db: Database) throws {
      try T.update { $0.primaryKey = $0.primaryKey }.execute(db)
    }

    private func uploadRecordsToCloudKit(tableName: String, db: Database) throws {
      guard let table = self.tablesByName[tableName]
      else { return }
      func open<T: PrimaryKeyedTable>(_: T.Type) throws {
        try uploadRecordsToCloudKit(table: T.self, db: db)
      }
      try open(table)
    }

    private func updateLocalFromSchemaChange(
      previousRecordTypeByTableName: [String: RecordType],
      currentRecordTypeByTableName: [String: RecordType]
    ) async throws {
      let tablesWithChangedSchemas = currentRecordTypeByTableName.filter { tableName, recordType in
        previousRecordTypeByTableName[tableName]?.schema != recordType.schema
      }

      for (tableName, currentRecordType) in tablesWithChangedSchemas {
        guard let table = tablesByName[tableName]
        else { continue }
        func open<T: PrimaryKeyedTable>(_: T.Type) async throws {
          let previousRecordType = previousRecordTypeByTableName[tableName]
          let changedColumns = currentRecordType.tableInfo.subtracting(
            previousRecordType?.tableInfo ?? []
          )
          .map(\.name)
          let lastKnownServerRecords = try await metadatabase.read { db in
            try SyncMetadata
              .where { $0.recordType.eq(tableName) }
              .select(\._lastKnownServerRecordAllFields)
              .fetchAll(db)
          }
          for case .some(let lastKnownServerRecord) in lastKnownServerRecords {
            let query = try await updateQuery(
              for: T.self,
              record: lastKnownServerRecord,
              columnNames: T.TableColumns.writableColumns.map(\.name),
              changedColumnNames: changedColumns
            )
            try await userDatabase.write { db in
              try #sql(query).execute(db)
            }
          }
        }
        try await open(table)
      }
    }

    package func tearDownSyncEngine() throws {
      try userDatabase.write { db in
        for table in tables.reversed() {
          try table.dropTriggers(db: db)
        }
        for trigger in SyncMetadata.callbackTriggers(for: self).reversed() {
          try trigger.drop().execute(db)
        }
        db.remove(function: $hasPermission)
        db.remove(function: $didDelete)
        db.remove(function: $didUpdate)
        db.remove(function: $syncEngineIsSynchronizingChanges)
        db.remove(function: $datetime)
      }
      try metadatabase.erase()
    }

    func deleteLocalData() throws {
      try tearDownSyncEngine()
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
      try setUpSyncEngine()
    }

    @DatabaseFunction(
      "sqlitedata_icloud_didUpdate",
      as: ((String, CKRecord?.SystemFieldsRepresentation) -> Void).self
    )
    func didUpdate(recordName: String, record: CKRecord?) {
      let zoneID = record?.recordID.zoneID ?? defaultZone.zoneID
      let change = CKSyncEngine.PendingRecordZoneChange.saveRecord(
        CKRecord.ID(
          recordName: recordName,
          zoneID: zoneID
        )
      )
      guard isRunning else {
        Task {
          await withErrorReporting(.sqliteDataCloudKitFailure) {
            try await userDatabase.write { db in
              try PendingRecordZoneChange
                .insert { PendingRecordZoneChange(change) }
                .execute(db)
            }
          }
        }
        return
      }

      let syncEngine = self.syncEngines.withValue {
        zoneID.ownerName == CKCurrentUserDefaultName ? $0.private : $0.shared
      }
      syncEngine?.state.add(pendingRecordZoneChanges: [change])
    }

    @DatabaseFunction(
      "sqlitedata_icloud_didDelete",
      as: ((String, CKRecord?.SystemFieldsRepresentation, CKShare?.SystemFieldsRepresentation)
        -> Void).self
    )
    func didDelete(recordName: String, record: CKRecord?, share: CKShare?) {
      let zoneID = record?.recordID.zoneID ?? defaultZone.zoneID
      var changes: [CKSyncEngine.PendingRecordZoneChange] = [
        .deleteRecord(
          CKRecord.ID(
            recordName: recordName,
            zoneID: zoneID
          )
        )
      ]
      if let share {
        changes.append(.deleteRecord(share.recordID))
      }
      guard isRunning else {
        Task { [changes] in
          await withErrorReporting(.sqliteDataCloudKitFailure) {
            try await userDatabase.write { db in
              try PendingRecordZoneChange
                .insert { changes.map { PendingRecordZoneChange($0) } }
                .execute(db)
            }
          }
        }
        return
      }

      let syncEngine = self.syncEngines.withValue {
        zoneID.ownerName == CKCurrentUserDefaultName ? $0.private : $0.shared
      }
      syncEngine?.state.add(pendingRecordZoneChanges: changes)
    }

    package func acceptShare(metadata: ShareMetadata) async throws {
      guard let rootRecordID = metadata.hierarchicalRootRecordID
      else {
        reportIssue("Attempting to share without root record information.")
        return
      }
      let container = type(of: container).createContainer(identifier: metadata.containerIdentifier)
      _ = try await container.accept(metadata)
      try await syncEngines.shared?.fetchChanges(
        CKSyncEngine.FetchChangesOptions(
          scope: .zoneIDs([rootRecordID.zoneID]),
          operationGroup: nil
        )
      )
    }

    /// A query expression that can be used in SQL queries to determine if the ``SyncEngine``
    /// is currently writing changes to the database.
    ///
    /// See <doc:CloudKit#Updating-triggers-to-be-compatible-with-synchronization> for more info.
    public static func isSynchronizingChanges() -> some QueryExpression<Bool> {
      $syncEngineIsSynchronizingChanges()
    }
  }

  extension PrimaryKeyedTable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    fileprivate static func createTriggers(
      foreignKeysByTableName: [String: [ForeignKey]],
      tablesByName: [String: any PrimaryKeyedTable.Type],
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
        await handleFetchedDatabaseChanges(
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
      var changes = await pendingRecordZoneChanges(options: options, syncEngine: syncEngine)
      guard !changes.isEmpty
      else { return nil }

      changes.sort { lhs, rhs in
        switch (lhs, rhs) {
        case (.saveRecord(let lhs), .saveRecord(let rhs)):
          guard
            let lhsRecordType = lhs.tableName,
            let lhsIndex = tablesByOrder[lhsRecordType],
            let rhsRecordType = rhs.tableName,
            let rhsIndex = tablesByOrder[rhsRecordType]
          else { return true }
          return lhsIndex < rhsIndex
        case (.deleteRecord(let lhs), .deleteRecord(let rhs)):
          guard
            let lhsRecordType = lhs.tableName,
            let lhsIndex = tablesByOrder[lhsRecordType],
            let rhsRecordType = rhs.tableName,
            let rhsIndex = tablesByOrder[rhsRecordType]
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
        var missingTable: CKRecord.ID?
        var missingRecord: CKRecord.ID?
        var sentRecord: CKRecord.ID?
        #if DEBUG
          defer {
            state.withValue { [missingTable, missingRecord, sentRecord] in
              if let missingTable { $0.missingTables.append(missingTable) }
              if let missingRecord { $0.missingRecords.append(missingRecord) }
              if let sentRecord { $0.sentRecords.append(sentRecord) }
            }
          }
        #endif

        guard
          let (metadata, allFields) = await withErrorReporting(
            .sqliteDataCloudKitFailure,
            catching: {
              try await metadatabase.read { db in
                try SyncMetadata
                  .where { $0.recordName.eq(recordID.recordName) }
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
        func open<T: PrimaryKeyedTable>(_: T.Type) async -> CKRecord? {
          let row =
            withErrorReporting(.sqliteDataCloudKitFailure) {
              try userDatabase.read { db in
                try T
                  .where {
                    #sql("\($0.primaryKey) = \(bind: metadata.recordPrimaryKey)")
                  }
                  .fetchOne(db)
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
          if let parentRecordName = metadata.parentRecordName,
            let parentRecordType = metadata.parentRecordType,
            !privateTables.contains(where: { $0.tableName == parentRecordType })
          {
            record.parent = CKRecord.Reference(
              recordID: CKRecord.ID(
                recordName: parentRecordName,
                zoneID: record.recordID.zoneID
              ),
              action: .none
            )
          } else {
            record.parent = nil
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

    private func pendingRecordZoneChanges(
      options: CKSyncEngine.SendChangesOptions,
      syncEngine: any SyncEngineProtocol
    ) async -> [CKSyncEngine.PendingRecordZoneChange] {
      var changes = syncEngine.state.pendingRecordZoneChanges.filter(options.scope.contains)
      guard !changes.isEmpty
      else { return [] }

      let deletedRecordIDs: [CKRecord.ID] = changes.compactMap {
        switch $0 {
        case .saveRecord(_):
          return nil
        case .deleteRecord(let recordID):
          return recordID
        @unknown default:
          return nil
        }
      }
      let deletedRecordNames = deletedRecordIDs.map(\.recordName)

      let (metadataOfDeletions, recordsWithRoot): ([SyncMetadata], [RecordWithRoot]) =
        await withErrorReporting(.sqliteDataCloudKitFailure) {
          try await metadatabase.read { db in
            let metadataOfDeletions = try SyncMetadata.where {
              $0.recordName.in(deletedRecordNames)
            }
            .fetchAll(db)

            let recordsWithRoot =
              try With {
                SyncMetadata
                  .where { $0.parentRecordName.is(nil) && $0.recordName.in(deletedRecordNames) }
                  .select {
                    RecordWithRoot.Columns(
                      parentRecordName: $0.parentRecordName,
                      recordName: $0.recordName,
                      lastKnownServerRecord: $0.lastKnownServerRecord,
                      rootRecordName: $0.recordName,
                      rootLastKnownServerRecord: $0.lastKnownServerRecord
                    )
                  }
                  .union(
                    all: true,
                    SyncMetadata
                      .join(RecordWithRoot.all) { $1.recordName.is($0.parentRecordName) }
                      .select { metadata, tree in
                        RecordWithRoot.Columns(
                          parentRecordName: metadata.parentRecordName,
                          recordName: metadata.recordName,
                          lastKnownServerRecord: metadata.lastKnownServerRecord,
                          rootRecordName: tree.rootRecordName,
                          rootLastKnownServerRecord: tree.lastKnownServerRecord
                        )
                      }
                  )
              } query: {
                RecordWithRoot
                  .where { $0.recordName.in(deletedRecordNames) }
              }
              .fetchAll(db)

            return (metadataOfDeletions, recordsWithRoot)
          }
        }
        ?? ([], [])

      let shareRecordIDsToDelete = metadataOfDeletions.compactMap(\.share?.recordID)

      for recordWithRoot in recordsWithRoot {
        guard
          let lastKnownServerRecord = recordWithRoot.lastKnownServerRecord,
          let rootLastKnownServerRecord = recordWithRoot.rootLastKnownServerRecord
        else { continue }
        guard let rootShareRecordID = rootLastKnownServerRecord.share?.recordID
        else { continue }
        guard shareRecordIDsToDelete.contains(rootShareRecordID)
        else { continue }
        changes.removeAll(where: { $0 == .deleteRecord(lastKnownServerRecord.recordID) })
        syncEngine.state.remove(
          pendingRecordZoneChanges: [.deleteRecord(lastKnownServerRecord.recordID)]
        )
      }

      await withErrorReporting(.sqliteDataCloudKitFailure) {
        try await userDatabase.write { db in
          try SyncMetadata
            .where { $0.recordName.in(deletedRecordNames) }
            .delete()
            .execute(db)
        }
      }

      return changes
    }

    package func handleAccountChange(
      changeType: CKSyncEngine.Event.AccountChange.ChangeType,
      syncEngine: any SyncEngineProtocol
    ) async {
      guard syncEngine === syncEngines.private
      else { return }

      switch changeType {
      case .signIn:
        syncEngine.state.add(pendingDatabaseChanges: [.saveZone(defaultZone)])
        await withErrorReporting(.sqliteDataCloudKitFailure) {
          try await userDatabase.write { db in
            for table in self.tables {
              try self.uploadRecordsToCloudKit(table: table, db: db)
            }
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
    ) async {
      let defaultZoneDeleted =
        await withErrorReporting(.sqliteDataCloudKitFailure) {
          try await userDatabase.write { db in
            var defaultZoneDeleted = false
            for (zoneID, reason) in deletions {
              guard zoneID == self.defaultZone.zoneID
              else { continue }
              switch reason {
              case .deleted, .purged:
                try deleteRecords(in: zoneID, db: db)
                defaultZoneDeleted = true
              case .encryptedDataReset:
                try uploadRecords(in: zoneID, db: db)
              @unknown default:
                reportIssue("Unknown deletion reason: \(reason)")
              }
            }
            return defaultZoneDeleted
          }
        }
        ?? false
      if defaultZoneDeleted {
        syncEngine.state.add(pendingDatabaseChanges: [.saveZone(self.defaultZone)])
      }
      @Sendable
      func deleteRecords(in zoneID: CKRecordZone.ID, db: Database) throws {
        let recordTypes = Set(
          try SyncMetadata
            .select(\.lastKnownServerRecord)
            .fetchAll(db)
            .compactMap { $0?.recordID.zoneID == zoneID ? $0?.recordType : nil }
        )
        for recordType in recordTypes {
          guard let table = tablesByName[recordType]
          else { continue }
          func open<T: PrimaryKeyedTable>(_: T.Type) {
            withErrorReporting(.sqliteDataCloudKitFailure) {
              try T.delete().execute(db)
            }
          }
          open(table)
        }
      }
      @Sendable
      func uploadRecords(in zoneID: CKRecordZone.ID, db: Database) throws {
        let recordTypes = Set(
          try SyncMetadata
            .select(\.lastKnownServerRecord)
            .fetchAll(db)
            .compactMap { $0?.recordID.zoneID == zoneID ? $0?.recordType : nil }
        )
        var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] = []
        for recordType in recordTypes {
          guard let table = tablesByName[recordType]
          else { continue }
          func open<T: PrimaryKeyedTable>(_: T.Type) {
            withErrorReporting(.sqliteDataCloudKitFailure) {
              pendingRecordZoneChanges.append(
                contentsOf: try T.select(\._recordName).fetchAll(db).map {
                  .saveRecord(CKRecord.ID(recordName: $0, zoneID: zoneID))
                }
              )
            }
          }
          open(table)
        }
        syncEngine.state.add(pendingRecordZoneChanges: pendingRecordZoneChanges)
      }
    }

    package func handleFetchedRecordZoneChanges(
      modifications: [CKRecord] = [],
      deletions: [(recordID: CKRecord.ID, recordType: CKRecord.RecordType)] = [],
      syncEngine: any SyncEngineProtocol
    ) async {
      let deletedRecordIDsByRecordType = OrderedDictionary(
        grouping: deletions.sorted { lhs, rhs in
          guard
            let lhsIndex = tablesByOrder[lhs.recordType],
            let rhsIndex = tablesByOrder[rhs.recordType]
          else { return true }
          return lhsIndex > rhsIndex
        },
        by: \.recordType
      )
      .mapValues { $0.map(\.recordID) }
      for (recordType, recordIDs) in deletedRecordIDsByRecordType {
        let recordPrimaryKeys = recordIDs.compactMap(\.recordPrimaryKey)
        if let table = tablesByName[recordType] {
          func open<T: PrimaryKeyedTable>(_: T.Type) {
            withErrorReporting(.sqliteDataCloudKitFailure) {
              try userDatabase.write { db in
                try T
                  .where {
                    $0.primaryKey.in(
                      recordPrimaryKeys.map { #sql("\(bind: $0)") }
                    )
                  }
                  .delete()
                  .execute(db)

                try UnsyncedRecordID
                  .findAll(recordIDs)
                  .delete()
                  .execute(db)
              }
            }
          }
          open(table)
        } else if recordType == CKRecord.SystemType.share {
          for recordID in recordIDs {
            withErrorReporting(.sqliteDataCloudKitFailure) {
              try deleteShare(recordID: recordID)
            }
          }
        } else {
          // NB: Deleting a record from a table we do not currently recognize.
        }
      }

      let unsyncedRecords =
        await withErrorReporting(.sqliteDataCloudKitFailure) {
          var unsyncedRecordIDs = try await userDatabase.write { db in
            Set(
              try UnsyncedRecordID.all
                .fetchAll(db)
                .map(CKRecord.ID.init(unsyncedRecordID:))
            )
          }
          let modificationRecordIDs = Set(modifications.map(\.recordID))
          let unsyncedRecordIDsToDelete = modificationRecordIDs.intersection(unsyncedRecordIDs)
          unsyncedRecordIDs.subtract(modificationRecordIDs)
          if !unsyncedRecordIDsToDelete.isEmpty {
            try await userDatabase.write { db in
              try UnsyncedRecordID
                .findAll(unsyncedRecordIDsToDelete)
                .delete()
                .execute(db)
            }
          }
          let results = try await syncEngine.database.records(for: Array(unsyncedRecordIDs))
          var unsyncedRecords: [CKRecord] = []
          for (recordID, result) in results {
            switch result {
            case .success(let record):
              unsyncedRecords.append(record)
            case .failure(let error as CKError) where error.code == .unknownItem:
              try await userDatabase.write { db in
                try UnsyncedRecordID.find(recordID).delete().execute(db)
              }
            case .failure:
              continue
            }
          }
          return unsyncedRecords
        }
        ?? [CKRecord]()

      let modifications = (modifications + unsyncedRecords).sorted { lhs, rhs in
        guard
          let lhsRecordType = lhs.recordID.tableName,
          let lhsIndex = tablesByOrder[lhsRecordType],
          let rhsRecordType = rhs.recordID.tableName,
          let rhsIndex = tablesByOrder[rhsRecordType]
        else { return true }
        return lhsIndex < rhsIndex
      }

      enum ShareOrReference {
        case share(CKShare)
        case reference(CKShare.Reference)
      }
      var shares: [ShareOrReference] = []
      for record in modifications {
        if let share = record as? CKShare {
          shares.append(.share(share))
        } else {
          upsertFromServerRecord(record)
          if let shareReference = record.share {
            shares.append(.reference(shareReference))
          }
        }
      }

      await withTaskGroup(of: Void.self) { group in
        for share in shares {
          group.addTask {
            switch share {
            case .share(let share):
              await withErrorReporting(.sqliteDataCloudKitFailure) {
                try await self.cacheShare(share)
              }
            case .reference(let shareReference):
              guard
                let record = try? await syncEngine.database.record(for: shareReference.recordID),
                let share = record as? CKShare
              else { return }
              await withErrorReporting(.sqliteDataCloudKitFailure) {
                try await self.cacheShare(share)
              }
            }
          }
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
      for (failedRecord, error) in failedRecordSaves {
        func clearServerRecord() {
          withErrorReporting(.sqliteDataCloudKitFailure) {
            try userDatabase.write { db in
              try SyncMetadata
                .where { $0.recordName.eq(failedRecord.recordID.recordName) }
                .update { $0.setLastKnownServerRecord(nil) }
                .execute(db)
            }
          }
        }

        switch error.code {
        case .serverRecordChanged:
          guard let serverRecord = error.serverRecord else { continue }
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

        case .referenceViolation:
          guard
            let recordPrimaryKey = failedRecord.recordID.recordPrimaryKey,
            let table = tablesByName[failedRecord.recordType],
            foreignKeysByTableName[table.tableName]?.count == 1,
            let foreignKey = foreignKeysByTableName[table.tableName]?.first
          else { continue }
          func open<T: PrimaryKeyedTable>(_: T.Type) throws {
            try userDatabase.write { db in
              try Self.$_isSynchronizingChanges.withValue(false) {
                switch foreignKey.onDelete {
                case .cascade:
                  try T
                    .where { #sql("\($0.primaryKey) = \(bind: recordPrimaryKey)") }
                    .delete()
                    .execute(db)
                case .restrict:
                  preconditionFailure(
                    "'RESTRICT' foreign key actions not supported for parent relationships."
                  )
                case .setDefault:
                  guard
                    let recordType = try RecordType.find(table.tableName).fetchOne(db),
                    let columnInfo = recordType.tableInfo.first(where: {
                      $0.name == foreignKey.from
                    })
                  else { return }
                  let defaultValue = columnInfo.defaultValue ?? "NULL"
                  try #sql(
                    """
                    UPDATE \(T.self)
                    SET \(quote: foreignKey.from, delimiter: .identifier) = (\(raw: defaultValue))
                    WHERE \(T.primaryKey) = \(bind: recordPrimaryKey)
                    """
                  )
                  .execute(db)
                  break
                case .setNull:
                  try #sql(
                    """
                    UPDATE \(T.self)
                    SET \(quote: foreignKey.from, delimiter: .identifier) = NULL
                    WHERE \(T.primaryKey) = \(bind: recordPrimaryKey)
                    """
                  )
                  .execute(db)
                case .noAction:
                  preconditionFailure(
                    "'NO ACTION' foreign key actions not supported for parent relationships."
                  )
                }
              }
            }
          }
          withErrorReporting(.sqliteDataCloudKitFailure) {
            try open(table)
          }

        case .permissionFailure:
          guard
            let recordPrimaryKey = failedRecord.recordID.recordPrimaryKey,
            let table = tablesByName[failedRecord.recordType]
          else { continue }
          func open<T: PrimaryKeyedTable>(_: T.Type) async throws {
            do {
              let serverRecord = try await container.sharedCloudDatabase.record(
                for: failedRecord.recordID
              )
              upsertFromServerRecord(serverRecord, force: true)
            } catch let error as CKError where error.code == .unknownItem {
              try await userDatabase.write { db in
                try T
                  .where { #sql("\($0.primaryKey) = \(bind: recordPrimaryKey)") }
                  .delete()
                  .execute(db)
              }
            }
          }
          await withErrorReporting(.sqliteDataCloudKitFailure) {
            try await open(table)
          }

        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable,
          .notAuthenticated, .operationCancelled, .batchRequestFailed,
          .internalError, .partialFailure, .badContainer, .requestRateLimited, .missingEntitlement,
          .invalidArguments, .resultsTruncated, .assetFileNotFound,
          .assetFileModified, .incompatibleVersion, .constraintViolation, .changeTokenExpired,
          .badDatabase, .quotaExceeded, .limitExceeded, .userDeletedZone, .tooManyParticipants,
          .alreadyShared, .managedAccountRestricted, .participantMayNeedVerification,
          .serverResponseLost, .assetNotAvailable, .accountTemporarilyUnavailable:
          continue
        @unknown default:
          continue
        }
      }

      let enqueuedUnsyncedRecordID =
        await withErrorReporting(.sqliteDataCloudKitFailure) {
          try await userDatabase.write { db in
            var enqueuedUnsyncedRecordID = false
            for (failedRecordID, error) in failedRecordDeletes {
              guard
                error.code == .referenceViolation
              else { continue }
              try UnsyncedRecordID.insert(or: .ignore) {
                UnsyncedRecordID(recordID: failedRecordID)
              }
              .execute(db)
              syncEngine.state.remove(pendingRecordZoneChanges: [.deleteRecord(failedRecordID)])
              enqueuedUnsyncedRecordID = true
            }
            return enqueuedUnsyncedRecordID
          }
        }
        ?? false
      if enqueuedUnsyncedRecordID {
        await handleFetchedRecordZoneChanges(syncEngine: syncEngine)
      }
    }

    private func cacheShare(_ share: CKShare) async throws {
      let metadata = try await container.shareMetadata(for: share, shouldFetchRootRecord: false)
      guard let rootRecordID = metadata.hierarchicalRootRecordID
      else { return }
      try await userDatabase.write { db in
        try SyncMetadata
          .where { $0.recordName.eq(rootRecordID.recordName) }
          .update { $0.share = share }
          .execute(db)
      }
    }

    func deleteShare(recordID: CKRecord.ID) throws {
      try userDatabase.write { db in
        let shareAndRecordName =
          try SyncMetadata
          .where(\.isShared)
          .select { ($0.share, $0.recordName) }
          .fetchAll(db)
          .first(where: { share, _ in share?.recordID == recordID }) ?? nil
        guard let (_, recordName) = shareAndRecordName
        else { return }
        try SyncMetadata
          .where { $0.recordName.eq(recordName) }
          .update { $0.share = nil }
          .execute(db)
      }
    }

    private func upsertFromServerRecord(
      _ serverRecord: CKRecord,
      force: Bool = false
    ) {
      withErrorReporting(.sqliteDataCloudKitFailure) {
        guard let table = tablesByName[serverRecord.recordType]
        else {
          guard let recordPrimaryKey = serverRecord.recordID.recordPrimaryKey
          else { return }
          try userDatabase.write { db in
            try SyncMetadata.insert {
              SyncMetadata(
                recordPrimaryKey: recordPrimaryKey,
                recordType: serverRecord.recordType,
                parentRecordPrimaryKey: serverRecord.parent?.recordID.recordPrimaryKey,
                parentRecordType: serverRecord.parent?.recordID.tableName,
                lastKnownServerRecord: serverRecord,
                _lastKnownServerRecordAllFields: serverRecord,
                share: nil,
                userModificationDate: serverRecord.userModificationDate
              )
            } onConflict: {
              ($0.recordPrimaryKey, $0.recordType)
            } doUpdate: {
              $0.setLastKnownServerRecord(serverRecord)
            }
            .execute(db)
          }
          return
        }

        let metadata = try metadatabase.read { db in
          try SyncMetadata
            .where { $0.recordName.eq(serverRecord.recordID.recordName) }
            .fetchOne(db)
        }
        serverRecord.userModificationDate =
          metadata?.userModificationDate ?? serverRecord.userModificationDate

        func open<T: PrimaryKeyedTable>(_: T.Type) throws {
          var columnNames = T.TableColumns.writableColumns.map(\.name)
          if !force, let metadata, let allFields = metadata._lastKnownServerRecordAllFields {
            let row = try userDatabase.read { db in
              try T.find(#sql("\(bind: metadata.recordPrimaryKey)")).fetchOne(db)
            }
            guard let row
            else {
              reportIssue(
                """
                Local database record could not be found for '\(serverRecord.recordID.recordName)'.
                """
              )
              return
            }
            serverRecord.update(
              with: allFields,
              row: T(queryOutput: row),
              columnNames: &columnNames,
              parentForeignKey: foreignKeysByTableName[T.tableName]?.count == 1
                ? foreignKeysByTableName[T.tableName]?.first
                : nil
            )
          }

          try userDatabase.write { db in
            do {
              try #sql(upsert(T.self, record: serverRecord, columnNames: columnNames)).execute(db)
              try UnsyncedRecordID.find(serverRecord.recordID).delete().execute(db)
              try SyncMetadata
                .where { $0.recordName.eq(serverRecord.recordID.recordName) }
                .update { $0.setLastKnownServerRecord(serverRecord) }
                .execute(db)
            } catch {
              guard
                let error = error as? DatabaseError,
                error.resultCode == .SQLITE_CONSTRAINT,
                error.extendedResultCode == .SQLITE_CONSTRAINT_FOREIGNKEY
              else {
                throw error
              }
              try UnsyncedRecordID.insert(or: .ignore) {
                UnsyncedRecordID(recordID: serverRecord.recordID)
              }
              .execute(db)
            }
          }
        }
        try open(table)
      }
    }

    private func refreshLastKnownServerRecord(_ record: CKRecord) async {
      let metadata = await metadataFor(recordName: record.recordID.recordName)

      func updateLastKnownServerRecord() {
        withErrorReporting(.sqliteDataCloudKitFailure) {
          try userDatabase.write { db in
            try SyncMetadata
              .where { $0.recordName.eq(record.recordID.recordName) }
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

    private func metadataFor(recordName: String) async -> SyncMetadata? {
      await withErrorReporting(.sqliteDataCloudKitFailure) {
        try await metadatabase.read { db in
          try SyncMetadata.where { $0.recordName.eq(recordName) }.fetchOne(db)
        }
      }
        ?? nil
    }

    private func updateQuery<T: PrimaryKeyedTable>(
      for _: T.Type,
      record: CKRecord,
      columnNames: some Collection<String>,
      changedColumnNames: some Collection<String>
    ) async throws -> QueryFragment {
      let nonPrimaryKeyChangedColumns =
        changedColumnNames
        .filter { $0 != T.columns.primaryKey.name }
      guard
        !nonPrimaryKeyChangedColumns.isEmpty
      else {
        return ""
      }
      var record = record
      let recordHasAsset = nonPrimaryKeyChangedColumns.contains { columnName in
        record[columnName] is CKAsset
      }
      if recordHasAsset {
        record = try await container.database(for: record.recordID).record(for: record.recordID)
      }

      var query: QueryFragment = "INSERT INTO \(T.self) ("
      query.append(columnNames.map { "\(quote: $0)" }.joined(separator: ", "))
      query.append(") VALUES (")
      query.append(
        columnNames
          .map { columnName in
            if let asset = record[columnName] as? CKAsset {
              let data = try? asset.fileURL.map { try dataManager.wrappedValue.load($0) }
              if data == nil {
                reportIssue("Asset data not found on disk")
              }
              return data?.queryFragment ?? "NULL"
            } else {
              return record.encryptedValues[columnName]?.queryFragment ?? "NULL"
            }
          }
          .joined(separator: ", ")
      )
      query.append(") ON CONFLICT(\(quote: T.columns.primaryKey.name)) DO UPDATE SET ")
      query.append(
        nonPrimaryKeyChangedColumns
          .map { columnName in
            if let asset = record[columnName] as? CKAsset {
              let data = try? asset.fileURL.map { try dataManager.wrappedValue.load($0) }
              if data == nil {
                reportIssue("Asset data not found on disk")
              }
              return "\(quote: columnName) = \(data?.queryFragment ?? "NULL")"
            } else {
              return
                "\(quote: columnName) = \(record.encryptedValues[columnName]?.queryFragment ?? "NULL")"
            }
          }
          .joined(separator: ",")
      )
      return query
    }
  }

  @available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
  extension CKSyncEngine.PendingRecordZoneChange {
    var id: CKRecord.ID? {
      switch self {
      case .saveRecord(let id):
        return id
      case .deleteRecord(let id):
        return id
      @unknown default:
        return nil
      }
    }
  }

  extension CKRecord.ID {
    var tableName: String? {
      guard
        let i = recordName.utf8.lastIndex(of: .init(ascii: ":")),
        let j = recordName.utf8.index(i, offsetBy: 1, limitedBy: recordName.utf8.endIndex)
      else { return nil }
      let recordTypeBytes = recordName.utf8[j...]
      guard !recordTypeBytes.isEmpty else { return nil }
      return String(Substring(recordTypeBytes))
    }

    var recordPrimaryKey: String? {
      guard
        let i = recordName.utf8.lastIndex(of: .init(ascii: ":"))
      else { return nil }
      let recordPrimaryKeyBytes = recordName.utf8[..<i]
      guard
        !recordPrimaryKeyBytes.isEmpty
      else { return nil }
      return String(Substring(recordPrimaryKeyBytes))
    }
  }

  extension String {
    package static let sqliteDataCloudKitSchemaName = "sqlitedata_icloud"
    package static let sqliteDataCloudKitFailure = "SQLiteData CloudKit Failure"
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension URL {
    package static func metadatabase(
      databasePath: String,
      containerIdentifier: String?
    ) throws -> URL {
      guard let databaseURL = URL(string: databasePath)
      else {
        struct InvalidDatabasePath: Error {}
        throw InvalidDatabasePath()
      }
      guard !databaseURL.isInMemory
      else {
        return URL(string: "file:\(String.sqliteDataCloudKitSchemaName)?mode=memory&cache=shared")!
      }
      return
        databaseURL
        .deletingLastPathComponent()
        .appending(component: ".\(databaseURL.deletingPathExtension().lastPathComponent)")
        .appendingPathExtension("metadata\(containerIdentifier.map { "-\($0)" } ?? "").sqlite")
    }

    package var isInMemory: Bool {
      path.isEmpty
        || path.hasPrefix(":memory:")
        || URLComponents(url: self, resolvingAgainstBaseURL: false)?
          .queryItems?
          .contains(where: { $0.name == "mode" && $0.value == "memory" })
          == true
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  package struct SyncEngines {
    private let rawValue: (private: any SyncEngineProtocol, shared: any SyncEngineProtocol)?
    init() {
      rawValue = nil
    }
    init(private: any SyncEngineProtocol, shared: any SyncEngineProtocol) {
      rawValue = (`private`, shared)
    }
    var isRunning: Bool {
      rawValue != nil
    }
    package var `private`: (any SyncEngineProtocol)? {
      guard let `private` = rawValue?.private
      else {
        reportIssue("Private sync engine has not been set.")
        return nil
      }
      return `private`
    }
    package var `shared`: (any SyncEngineProtocol)? {
      guard let `shared` = rawValue?.shared
      else {
        reportIssue("Shared sync engine has not been set.")
        return nil
      }
      return `shared`
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
    ///     db.attachMetadatabase()
    ///     …
    ///   }
    /// }
    /// ```
    ///
    /// By default this method will use the container identifier assigned in your app's
    /// entitlements. If you wish to use a different container identifier then you can provide
    /// the `containerIdentifier` argument.
    ///
    /// See <doc:PreparingDatabase> for more information on preparing your database.
    ///
    /// - Parameter containerIdentifier: The identifier of the CloudKit container used to
    /// synchronize data. Defaults to the value set in the app's entitlements.
    public func attachMetadatabase(containerIdentifier: String? = nil) throws {
      let containerIdentifier =
        containerIdentifier
        ?? ModelConfiguration(groupContainer: .automatic).cloudKitContainerIdentifier

      guard let containerIdentifier else {
        throw SyncEngine.SchemaError(
          reason: .noCloudKitContainer,
          debugDescription: """
            No default CloudKit container found. Please add a container identifier to your app's \
            entitlements.
            """
        )
      }

      let databasePath = try #sql(
        """
        SELECT "file" FROM pragma_database_list()
        """,
        as: String.self
      )
      .fetchOne(self)
      guard let databasePath else {
        struct PathError: Error {}
        throw SyncEngine.SchemaError(
          reason: .unknown,
          debugDescription: """
            Expected to load a database path from the connection, but failed to do so.
            """
        )
      }
      let url = try URL.metadatabase(
        databasePath: databasePath,
        containerIdentifier: containerIdentifier
      )
      let path = url.path(percentEncoded: false)
      try FileManager.default.createDirectory(
        at: .applicationSupportDirectory,
        withIntermediateDirectories: true
      )
      _ = try DatabasePool(path: path).write { db in
        try #sql("SELECT 1").execute(db)
      }
      try #sql(
        """
        ATTACH DATABASE \(bind: path) AS \(quote: .sqliteDataCloudKitSchemaName)
        """
      )
      .execute(self)
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncEngine {
    struct SchemaError: LocalizedError {
      enum Reason {
        case inMemoryDatabase
        case invalidForeignKey(ForeignKey)
        case invalidForeignKeyAction(ForeignKey)
        case invalidTableName(String)
        case metadatabaseMismatch(attachedPath: String, syncEngineConfiguredPath: String)
        case noCloudKitContainer
        case nonNullColumnsWithoutDefault(tableName: String, columnNames: [String])
        case unknown
        case uniquenessConstraint
      }
      let reason: Reason
      let debugDescription: String

      var errorDescription: String? {
        "Could not synchronize data with iCloud."
      }
    }

    fileprivate func validateSchema() throws {
      let tableNames = Set(tables.map { $0.tableName })
      for tableName in tableNames {
        if tableName.contains(":") {
          throw SyncEngine.SchemaError(
            reason: .invalidTableName(tableName),
            debugDescription: "Table name contains invalid character ':'"
          )
        }
      }
      try userDatabase.read { db in
        for (tableName, foreignKeys) in foreignKeysByTableName {
          let invalidForeignKey = foreignKeys.first(where: { tablesByName[$0.table] == nil })
          if let invalidForeignKey {
            throw SyncEngine.SchemaError(
              reason: .invalidForeignKey(invalidForeignKey),
              debugDescription: """
                Foreign key \(tableName.debugDescription).\(invalidForeignKey.from.debugDescription) \
                references table \(invalidForeignKey.table.debugDescription) that is not \
                synchronized. Update 'SyncEngine.init' to synchronize \
                \(invalidForeignKey.table.debugDescription). 
                """
            )
          }

          if foreignKeys.count == 1,
            let foreignKey = foreignKeys.first,
            [.restrict, .noAction].contains(foreignKey.onDelete)
          {
            throw SyncEngine.SchemaError(
              reason: .invalidForeignKeyAction(foreignKey),
              debugDescription: """
                Foreign key \(tableName.debugDescription).\(foreignKey.from.debugDescription) action \
                not supported. Must be 'CASCADE', 'SET DEFAULT' or 'SET NULL'.
                """
            )
          }
        }

        for table in tables {
          let columnsWithUniqueConstraints =
            try #sql(
              """
              SELECT "name" FROM pragma_index_list(\(quote: table.tableName, delimiter: .text))
              WHERE "unique" = 1 AND "origin" <> 'pk'
              """,
              as: String.self
            )
            .fetchAll(db)
          if !columnsWithUniqueConstraints.isEmpty {
            throw SyncEngine.SchemaError(
              reason: .uniquenessConstraint,
              debugDescription: """
                Uniqueness constraints are not supported for synchronized tables.
                """
            )
          }
        }
      }
    }
  }

  private struct HashablePrimaryKeyedTableType: Hashable {
    let type: any PrimaryKeyedTable.Type
    init(_ type: any PrimaryKeyedTable.Type) {
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
    tables: [any PrimaryKeyedTable.Type],
    tablesByName: [String: any PrimaryKeyedTable.Type]
  ) throws -> [String: Int] {
    let tableDependencies = try userDatabase.read { db in
      var dependencies: [HashablePrimaryKeyedTableType: [any PrimaryKeyedTable.Type]] = [:]
      for table in tables {
        let toTables = try #sql(
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
  private func upsert<T: PrimaryKeyedTable>(
    _: T.Type,
    record: CKRecord,
    columnNames: some Collection<String>
  ) -> QueryFragment {
    let allColumnNames = T.TableColumns.writableColumns.map(\.name)
    let hasNonPrimaryKeyColumns = columnNames.contains(where: { $0 != T.columns.primaryKey.name })
    var query: QueryFragment = "INSERT INTO \(T.self) ("
    query.append(allColumnNames.map { "\(quote: $0)" }.joined(separator: ", "))
    query.append(") VALUES (")
    query.append(
      allColumnNames
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
    query.append(") ON CONFLICT(\(quote: T.columns.primaryKey.name)) DO ")
    if hasNonPrimaryKeyColumns {
      query.append("UPDATE SET ")
      query.append(
        columnNames
          .filter { columnName in columnName != T.columns.primaryKey.name }
          .map {
            """
            \(quote: $0) = "excluded".\(quote: $0)
            """
          }
          .joined(separator: ", ")
      )
    } else {
      query.append("NOTHING")
    }
    return query
  }
#endif
