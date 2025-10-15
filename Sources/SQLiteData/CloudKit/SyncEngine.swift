#if canImport(CloudKit)
  import CloudKit
  import ConcurrencyExtras
  import Dependencies
  import OrderedCollections
  import OSLog
  import Observation
  import StructuredQueriesCore
  import SwiftData
  import TabularData

  #if canImport(UIKit)
    import UIKit
  #endif

  /// An object that manages the synchronization of local and remote SQLite data.
  ///
  /// See <doc:CloudKit> for more information.
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  public final class SyncEngine: Observable, Sendable {
    package let userDatabase: UserDatabase
    package let logger: Logger
    package let metadatabase: any DatabaseWriter
    package let tables: [any SynchronizableTable]
    package let privateTables: [any SynchronizableTable]
    let tablesByName: [String: any SynchronizableTable]
    private let tablesByOrder: [String: Int]
    let foreignKeysByTableName: [String: [ForeignKey]]
    package let syncEngines = LockIsolated<SyncEngines>(SyncEngines())
    package let defaultZone: CKRecordZone
    let delegate: (any SyncEngineDelegate)?
    let defaultSyncEngines:
      @Sendable (any DatabaseReader, SyncEngine)
        -> (private: any SyncEngineProtocol, shared: any SyncEngineProtocol)
    package let container: any CloudContainer
    let dataManager = Dependency(\.dataManager)
    private let observationRegistrar = ObservationRegistrar()
    private let notificationsObserver = LockIsolated<(any NSObjectProtocol)?>(nil)
    private let activityCounts = LockIsolated(ActivityCounts())

    /// The error message used when a write occurs to a record for which the current user does not
    /// have permission.
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
    ///     shareable with other users on CloudKit.
    ///   - privateTables: A list of tables that you want to synchronize to CloudKit but that
    ///     you do not want to be shareable with other users.
    ///   - containerIdentifier: The container identifier in CloudKit to synchronize to. If omitted
    ///     the container will be determined from the entitlements of your app.
    ///   - defaultZone: The zone for all records to be stored in.
    ///   - startImmediately: Determines if the sync engine starts right away or requires an
    ///     explicit call to ``start()``. By default this argument is `true`.
    ///   - delegate: A delegate object that can override default sync engine behavior.
    ///   - logger: The logger used to log events in the sync engine. By default a `.disabled`
    ///     logger is used, which means logs are not printed.
    public convenience init<
      each T1: PrimaryKeyedTable & _SendableMetatype,
      each T2: PrimaryKeyedTable & _SendableMetatype
    >(
      for database: any DatabaseWriter,
      tables: repeat (each T1).Type,
      privateTables: repeat (each T2).Type,
      containerIdentifier: String? = nil,
      defaultZone: CKRecordZone = CKRecordZone(zoneName: "co.pointfree.SQLiteData.defaultZone"),
      startImmediately: Bool = DependencyValues._current.context == .live,
      delegate: (any SyncEngineDelegate)? = nil,
      logger: Logger = isTesting
        ? Logger(.disabled) : Logger(subsystem: "SQLiteData", category: "CloudKit")
    ) throws
    where
      repeat (each T1).PrimaryKey.QueryOutput: IdentifierStringConvertible,
      repeat (each T1).TableColumns.PrimaryColumn: WritableTableColumnExpression,
      repeat (each T2).PrimaryKey.QueryOutput: IdentifierStringConvertible,
      repeat (each T2).TableColumns.PrimaryColumn: WritableTableColumnExpression
    {
      let containerIdentifier =
        containerIdentifier
        ?? ModelConfiguration(groupContainer: .automatic).cloudKitContainerIdentifier

      var allTables: [any SynchronizableTable] = []
      var allPrivateTables: [any SynchronizableTable] = []
      for table in repeat each tables {
        allTables.append(SynchronizedTable(for: table))
      }
      for privateTable in repeat each privateTables {
        allPrivateTables.append(SynchronizedTable(for: privateTable))
      }
      let userDatabase = UserDatabase(database: database)

      @Dependency(\.context) var context
      guard context == .live
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
                parentSyncEngine: syncEngine,
                state: MockSyncEngineState()
              ),
              shared: MockSyncEngine(
                database: sharedDatabase,
                parentSyncEngine: syncEngine,
                state: MockSyncEngineState()
              )
            )
          },
          userDatabase: userDatabase,
          logger: logger,
          delegate: delegate,
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
        throw SchemaError.noCloudKitContainer
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
        delegate: delegate,
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
      delegate: (any SyncEngineDelegate)?,
      tables: [any SynchronizableTable],
      privateTables: [any SynchronizableTable] = []
    ) throws {
      let allTables = Set((tables + privateTables).map(HashableSynchronizedTable.init))
        .map(\.type)
      self.tables = allTables
      self.privateTables = privateTables
      self.delegate = delegate

      let foreignKeysByTableName = Dictionary(
        uniqueKeysWithValues: try userDatabase.read { db in
          try allTables.map { table -> (String, [ForeignKey]) in
            func open<T>(
              _: some SynchronizableTable<T>
            ) throws -> (String, [ForeignKey]) {
              (
                T.tableName,
                try PragmaForeignKeyList<T>
                  .join(PragmaTableInfo<T>.all) { $0.from.eq($1.name) }
                  .select {
                    ForeignKey.Columns(
                      table: $0.table,
                      from: $0.from,
                      to: $0.to,
                      onUpdate: $0.onUpdate,
                      onDelete: $0.onDelete,
                      isNotNull: $1.isNotNull
                    )
                  }
                  .fetchAll(db)
              )
            }
            return try open(table)
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
      self.tablesByName = Dictionary(
        uniqueKeysWithValues: self.tables.map { ($0.base.tableName, $0) }
      )
      self.foreignKeysByTableName = foreignKeysByTableName
      tablesByOrder = try SQLiteData.tablesByOrder(
        userDatabase: userDatabase,
        tables: allTables,
        tablesByName: tablesByName
      )
      #if os(iOS)
        @Dependency(\.defaultNotificationCenter) var defaultNotificationCenter
        notificationsObserver.withValue {
          $0 = defaultNotificationCenter.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: nil
          ) { [syncEngines] _ in
            Task { @MainActor in
              let taskIdentifier = UIApplication.shared.beginBackgroundTask()
              defer { UIApplication.shared.endBackgroundTask(taskIdentifier) }
              let (privateSyncEngine, sharedSyncEngine) = syncEngines.withValue {
                ($0.private, $0.shared)
              }
              try await privateSyncEngine?.sendChanges(CKSyncEngine.SendChangesOptions())
              try await sharedSyncEngine?.sendChanges(CKSyncEngine.SendChangesOptions())
            }
          }
        }
      #endif
      try validateSchema()
    }

    deinit {
      notificationsObserver.withValue {
        guard let observer = $0
        else { return }
        NotificationCenter.default.removeObserver(observer)
      }
    }

    nonisolated package func setUpSyncEngine() throws {
      try userDatabase.write { db in
        try setUpSyncEngine(writableDB: db)
      }
    }

    nonisolated package func setUpSyncEngine(writableDB db: Database) throws {
      let attachedMetadatabasePath: String? =
        try PragmaDatabaseList
        .where { $0.name.eq(String.sqliteDataCloudKitSchemaName) }
        .select(\.file)
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
      db.add(function: $currentTime)
      db.add(function: $syncEngineIsSynchronizingChanges)
      db.add(function: $didUpdate)
      db.add(function: $didDelete)
      db.add(function: $hasPermission)
      db.add(function: $currentZoneName)
      db.add(function: $currentOwnerName)

      for trigger in SyncMetadata.callbackTriggers(for: self) {
        try trigger.execute(db)
      }

      for table in tables {
        try table.base.createTriggers(
          foreignKeysByTableName: foreignKeysByTableName,
          tablesByName: tablesByName,
          defaultZone: defaultZone,
          db: db
        )
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
    
    /// Determines if the sync engine is currently sending local changes to the CloudKit server.
    ///
    /// It is an observable value, which means if it is accessed in a SwiftUI view, or some other
    /// observable context, then the view will automatically re-render when the value changes. As
    /// such, it can be useful for displaying a progress view to indicate that work is currently
    /// being done to synchronize changes.
    public var isSendingChanges: Bool {
      sendingChangesCount > 0
    }

    /// Determines if the sync engine is currently processing changes being sent to the device
    /// from CloudKit.
    ///
    /// It is an observable value, which means if it is accessed in a SwiftUI view, or some other
    /// observable context, then the view will automatically re-render when the value changes. As
    /// such, it can be useful for displaying a progress view to indicate that work is currently
    /// being done to synchronize changes.
    public var isFetchingChanges: Bool {
      fetchingChangesCount > 0
    }

    /// Determines if the sync engine is currently sending or receiving changes from CloudKit.
    ///
    /// This value is true if either of ``isSendingChanges`` or ``isFetchingChanges`` is true.
    /// It is an observable value, which means if it is accessed in a SwiftUI view, or some other
    /// observable context, then the view will automatically re-render when the value changes. As
    /// such, it can be useful for displaying a progress view to indicate that work is currently
    /// being done to synchronize changes.
    public var isSynchronizing: Bool {
      isSendingChanges || isFetchingChanges
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
      observationRegistrar.withMutation(of: self, keyPath: \.isRunning) {
        syncEngines.withValue {
          let (privateSyncEngine, sharedSyncEngine) = defaultSyncEngines(metadatabase, self)
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
              && $0.tableName.in(tables.map { $0.base.tableName })
          }
          .fetchAll(db)
        return try namesAndSchemas.compactMap { schema -> RecordType? in
          guard let sql = schema.sql, let table = tablesByName[schema.name]
          else { return nil }
          func open<T>(_: some SynchronizableTable<T>) throws -> RecordType {
            try RecordType(
              tableName: schema.name,
              schema: sql,
              tableInfo: Set(
                PragmaTableInfo<T>
                  .select {
                    TableInfo.Columns(
                      defaultValue: $0.defaultValue,
                      isPrimaryKey: $0.isPrimaryKey,
                      name: $0.name,
                      isNotNull: $0.isNotNull,
                      type: $0.type
                    )
                  }
                  .fetchAll(db)
              )
            )
          }
          return try open(table)
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
      try await enqueueLocallyPendingChanges()
      try await userDatabase.write { db in
        try PendingRecordZoneChange.delete().execute(db)

        let newTableNames = currentRecordTypeByTableName.keys.filter { tableName in
          previousRecordTypeByTableName[tableName] == nil
        }

        try $_isSynchronizingChanges.withValue(false) {
          for tableName in newTableNames {
            try self.uploadRecordsToCloudKit(tableName: tableName, db: db)
          }
        }
      }
    }

    private func enqueueLocallyPendingChanges() async throws {
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
    }

    private func enqueueUnknownRecordsForCloudKit() async throws {
      try await userDatabase.write { db in
        try $_isSynchronizingChanges.withValue(false) {
          try SyncMetadata
            .where { !$0.hasLastKnownServerRecord }
            .update { $0.recordPrimaryKey = $0.recordPrimaryKey }
            .execute(db)
        }
      }
    }

    private func uploadRecordsToCloudKit<T>(
      table: some SynchronizableTable<T>,
      db: Database
    ) throws {
      // try T.update { $0.primaryKey = $0.primaryKey }.execute(db)
      try #sql(
        """
        UPDATE \(T.self) SET \(quote: T.primaryKey.name) = \(quote: T.primaryKey.name)
        """
      )
      .execute(db)
    }

    private func uploadRecordsToCloudKit(tableName: String, db: Database) throws {
      guard let table = self.tablesByName[tableName]
      else { return }
      func open<T>(_ table: some SynchronizableTable<T>) throws {
        try uploadRecordsToCloudKit(table: table, db: db)
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
        func open<T>(_ table: some SynchronizableTable<T>) async throws {
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
              for: table,
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
          try table.base.dropTriggers(defaultZone: defaultZone, db: db)
        }
        for trigger in SyncMetadata.callbackTriggers(for: self).reversed() {
          try trigger.drop().execute(db)
        }
      }
      try metadatabase.erase()
      try migrate(metadatabase: metadatabase)
    }

    // Deletes synchronized data locally on device and restarts the sync engine.
    //
    // This method is called automatically by the sync engine when it detects the device's iCloud
    // account has logged out or changed. To customize this behavior, provide a
    // ``SyncEngineDelegate`` to the sync engine and implement
    // ``SyncEngineDelegate/syncEngine(_:accountChanged:)``.
    //
    // > Important: It is only appropriate to call this method when the device's iCloud account
    // > logs out or changes.
    public func deleteLocalData() async throws {
      stop()
      try tearDownSyncEngine()
      await withErrorReporting(.sqliteDataCloudKitFailure) {
        try await userDatabase.write { db in
          for table in tables {
            func open<T>(_: some SynchronizableTable<T>) {
              withErrorReporting(.sqliteDataCloudKitFailure) {
                try T.delete().execute(db)
              }
            }
            open(table)
          }
          try setUpSyncEngine(writableDB: db)
        }
      }
      try await start()
    }

    @DatabaseFunction(
      "sqlitedata_icloud_didUpdate",
      as: ((
        String,
        String,
        String,
        String,
        String,
        [String]?.JSONRepresentation
      ) -> Void).self
    )
    func didUpdate(
      recordName: String,
      zoneName: String,
      ownerName: String,
      oldZoneName: String,
      oldOwnerName: String,
      descendantRecordNames: [String]?
    ) {
      var oldChanges: [CKSyncEngine.PendingRecordZoneChange] = []
      var newChanges: [CKSyncEngine.PendingRecordZoneChange] = []

      let oldZoneID = CKRecordZone.ID(zoneName: oldZoneName, ownerName: oldOwnerName)
      let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)

      if oldZoneID != zoneID {
        oldChanges.append(.deleteRecord(CKRecord.ID(recordName: recordName, zoneID: oldZoneID)))
        for descendantRecordName in descendantRecordNames ?? [] {
          oldChanges.append(
            .deleteRecord(CKRecord.ID(recordName: descendantRecordName, zoneID: oldZoneID))
          )
        }
        newChanges.append(.saveRecord(CKRecord.ID(recordName: recordName, zoneID: zoneID)))
        for descendantRecordName in descendantRecordNames ?? [] {
          newChanges.append(
            .saveRecord(CKRecord.ID(recordName: descendantRecordName, zoneID: zoneID))
          )
        }
      } else {
        newChanges.append(
          .saveRecord(CKRecord.ID(recordName: recordName, zoneID: zoneID))
        )
      }

      guard isRunning else {
        // TODO: Perform this work in a trigger instead of a task.
        Task { [changes = oldChanges + newChanges] in
          await withErrorReporting(.sqliteDataCloudKitFailure) {
            try await userDatabase.write { db in
              try PendingRecordZoneChange
                .insert {
                  for change in changes {
                    PendingRecordZoneChange(change)
                  }
                }
                .execute(db)
            }
          }
        }
        return
      }
      let oldSyncEngine = self.syncEngines.withValue {
        oldZoneID.ownerName == CKCurrentUserDefaultName ? $0.private : $0.shared
      }
      let syncEngine = self.syncEngines.withValue {
        zoneID.ownerName == CKCurrentUserDefaultName ? $0.private : $0.shared
      }
      oldSyncEngine?.state.add(pendingRecordZoneChanges: oldChanges)
      syncEngine?.state.add(pendingRecordZoneChanges: newChanges)
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

    private var sendingChangesCount: Int {
      get {
        observationRegistrar.access(self, keyPath: \.isSendingChanges)
        return activityCounts.withValue(\.sendingChangesCount)
      }
      set {
        observationRegistrar.withMutation(of: self, keyPath: \.isSendingChanges) {
          activityCounts.withValue { $0.sendingChangesCount = newValue }
        }
      }
    }
    private var fetchingChangesCount: Int {
      get {
        observationRegistrar.access(self, keyPath: \.isFetchingChanges)
        return activityCounts.withValue(\.fetchingChangesCount)
      }
      set {
        observationRegistrar.withMutation(of: self, keyPath: \.isFetchingChanges) {
          activityCounts.withValue { $0.fetchingChangesCount = newValue }
        }
      }
    }
  }

  extension PrimaryKeyedTable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    fileprivate static func createTriggers(
      foreignKeysByTableName: [String: [ForeignKey]],
      tablesByName: [String: any SynchronizableTable],
      defaultZone: CKRecordZone,
      db: Database
    ) throws {
      let parentForeignKey =
        foreignKeysByTableName[tableName]?.count == 1
        ? foreignKeysByTableName[tableName]?.first
        : nil

      for trigger in metadataTriggers(parentForeignKey: parentForeignKey, defaultZone: defaultZone)
      {
        try trigger.execute(db)
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    fileprivate static func dropTriggers(defaultZone: CKRecordZone, db: Database) throws {
      for trigger in metadataTriggers(parentForeignKey: nil, defaultZone: defaultZone).reversed() {
        try trigger.drop().execute(db)
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension SyncEngine: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
      guard let event = Event(event)
      else {
        reportIssue("Unrecognized event received: \(event)")
        return
      }
      await handleEvent(event, syncEngine: syncEngine)
    }

    package func handleEvent(_ event: Event, syncEngine: any SyncEngineProtocol) async {
      #if DEBUG
        logger.log(event, syncEngine: syncEngine)
      #endif

      switch event {
      case .accountChange(let changeType):
        await handleAccountChange(changeType: changeType, syncEngine: syncEngine)
      case .stateUpdate(let stateSerialization):
        await handleStateUpdate(stateSerialization: stateSerialization, syncEngine: syncEngine)
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

      case .willFetchRecordZoneChanges:
        fetchingChangesCount += 1
      case .didFetchRecordZoneChanges:
        fetchingChangesCount -= 1

      case .willFetchChanges:
        fetchingChangesCount += 1
      case .didFetchChanges:
        fetchingChangesCount -= 1

      case .willSendChanges:
        sendingChangesCount += 1
      case .didSendChanges:
        sendingChangesCount -= 1

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
        let state = LockIsolated(NextRecordZoneChangeBatchLoggingState())
        defer {
          let state = state.withValue(\.self)
          if let tabularDescription = state.tabularDescription {
            logger.debug(
              """
              SQLiteData (\(syncEngine.database.databaseScope.label).db) \
              nextRecordZoneChangeBatch: \(reason)
                \(tabularDescription)
              """
            )
          }
        }
      #endif

      let batch = await syncEngine.recordZoneChangeBatch(pendingChanges: changes) { recordID in
        guard
          let (metadata, allFields) = await withErrorReporting(
            .sqliteDataCloudKitFailure,
            catching: {
              try await metadatabase.read { db in
                try SyncMetadata
                  .find(recordID)
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

        var missingTable: CKRecord.ID?
        var missingRecord: CKRecord.ID?
        var sentRecord: CKRecord.ID?
        #if DEBUG
          defer {
            state.withValue { [missingTable, missingRecord, sentRecord] in
              if let missingTable {
                $0.events.append("⚠️ Missing table")
                $0.recordTypes.append(metadata.recordType)
                $0.recordNames.append(missingTable.recordName)
              }
              if let missingRecord {
                $0.events.append("⚠️ Missing record")
                $0.recordTypes.append(metadata.recordType)
                $0.recordNames.append(missingRecord.recordName)
              }
              if let sentRecord {
                $0.events.append("➡️ Sending")
                $0.recordTypes.append(metadata.recordType)
                $0.recordNames.append(sentRecord.recordName)
              }
            }
          }
        #endif

        guard let table = tablesByName[metadata.recordType]
        else {
          syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
          missingTable = recordID
          return nil
        }
        func open<T>(_: some SynchronizableTable<T>) async -> CKRecord? {
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
            !privateTables.contains(where: { $0.base.tableName == parentRecordType })
          {
            record.parent = CKRecord.Reference(
              recordID: CKRecord.ID(
                recordName: parentRecordName,
                zoneID: recordID.zoneID
              ),
              action: .none
            )
          } else {
            record.parent = nil
          }

          record.update(
            with: T(queryOutput: row),
            userModificationTime: metadata.userModificationTime
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

      let (sharesToDelete, recordsWithRoot):
        ([CKShare?], [(lastKnownServerRecord: CKRecord?, rootLastKnownServerRecord: CKRecord?)]) =
          await withErrorReporting(.sqliteDataCloudKitFailure) {
            guard !deletedRecordIDs.isEmpty
            else { return ([], []) }

            return try await metadatabase.read { db in
              let sharesToDelete =
                try SyncMetadata
                .findAll(deletedRecordIDs)
                .where(\.isShared)
                .select(\.share)
                .fetchAll(db)

              let recordsWithRoot =
                try With {
                  SyncMetadata
                    .findAll(deletedRecordIDs)
                    .where { $0.parentRecordName.is(nil) }
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
                    .select { ($0.lastKnownServerRecord, $0.rootLastKnownServerRecord) }
                }
                .fetchAll(db)

              return (sharesToDelete, recordsWithRoot)
            }
          }
          ?? ([], [])

      let shareRecordIDsToDelete = sharesToDelete.compactMap(\.?.recordID)

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
        guard !deletedRecordIDs.isEmpty
        else { return }
        try await userDatabase.write { db in
          try SyncMetadata
            .findAll(deletedRecordIDs)
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
        await withErrorReporting {
          try await enqueueUnknownRecordsForCloudKit()
        }
      case .signOut, .switchAccounts:
        await notifyDelegate(changeType: changeType)

      @unknown default:
        break
      }

      func notifyDelegate(changeType: CKSyncEngine.Event.AccountChange.ChangeType) async {
        guard let delegate
        else {
          await withErrorReporting(.sqliteDataCloudKitFailure) {
            try await deleteLocalData()
          }
          return
        }
        await delegate.syncEngine(self, accountChanged: changeType)
      }
    }

    package func handleStateUpdate(
      stateSerialization: CKSyncEngine.State.Serialization,
      syncEngine: any SyncEngineProtocol
    ) async {
      await withErrorReporting(.sqliteDataCloudKitFailure) {
        try await userDatabase.write { db in
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
              switch reason {
              case .deleted, .purged:
                try deleteRecords(in: zoneID, db: db)
                if zoneID == self.defaultZone.zoneID {
                  defaultZoneDeleted = true
                }
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
        let recordTypes = Dictionary(
          grouping:
            try SyncMetadata
            .where { $0.zoneName.eq(zoneID.zoneName) && $0.ownerName.eq(zoneID.ownerName) }
            .select { ($0.recordType, $0.recordPrimaryKey) }
            .fetchAll(db),
          by: \.0
        )
        .mapValues {
          $0.map(\.1)
        }
        for (recordType, primaryKeys) in recordTypes {
          guard let table = tablesByName[recordType]
          else { continue }
          func open<T: PrimaryKeyedTable>(_: some SynchronizableTable<T>) {
            withErrorReporting(.sqliteDataCloudKitFailure) {
              try T.where { #sql("\($0.primaryKey)").in(primaryKeys) }.delete().execute(db)
            }
          }
          open(table)
        }
      }
      @Sendable
      func uploadRecords(in zoneID: CKRecordZone.ID, db: Database) throws {
        let recordTypes = Set(
          try SyncMetadata
            .where(\.hasLastKnownServerRecord)
            .select(\.lastKnownServerRecord)
            .fetchAll(db)
            .compactMap { $0?.recordID.zoneID == zoneID ? $0?.recordType : nil }
        )
        var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] = []
        for recordType in recordTypes {
          guard let table = tablesByName[recordType]
          else { continue }
          func open<T>(_: some SynchronizableTable<T>) {
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
        if let table = tablesByName[recordType] {
          func open<T>(_: some SynchronizableTable<T>) async {
            await withErrorReporting(.sqliteDataCloudKitFailure) {
              try await userDatabase.write { db in
                try T
                  .where {
                    #sql("\($0.primaryKey)").in(
                      SyncMetadata.findAll(recordIDs)
                        .select(\.recordPrimaryKey)
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
          await open(table)
        } else if recordType == CKRecord.SystemType.share {
          for shareRecordID in recordIDs {
            await withErrorReporting(.sqliteDataCloudKitFailure) {
              try await deleteShare(shareRecordID: shareRecordID)
            }
          }
        } else {
          // NB: Deleting a record from a table we do not currently recognize.
          await withErrorReporting(.sqliteDataCloudKitFailure) {
            try await userDatabase.write { db in
              try SyncMetadata
                .findAll(recordIDs)
                .delete()
                .execute(db)
            }
          }
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
      let shares: [ShareOrReference] =
        await withErrorReporting(.sqliteDataCloudKitFailure) {
          try await userDatabase.write { db in
            var shares: [ShareOrReference] = []
            for record in modifications {
              if let share = record as? CKShare {
                shares.append(.share(share))
              } else {
                upsertFromServerRecord(record, db: db)
                if let shareReference = record.share {
                  shares.append(.reference(shareReference))
                }
              }
            }
            return shares
          }
        }
        ?? []

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
        func clearServerRecord() async {
          await withErrorReporting(.sqliteDataCloudKitFailure) {
            try await userDatabase.write { db in
              try SyncMetadata
                .find(failedRecord.recordID)
                .update { $0.setLastKnownServerRecord(nil) }
                .execute(db)
            }
          }
        }

        switch error.code {
        case .serverRecordChanged:
          guard let serverRecord = error.serverRecord else { continue }
          await upsertFromServerRecord(serverRecord)
          newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))

        case .zoneNotFound:
          let zone = CKRecordZone(zoneID: failedRecord.recordID.zoneID)
          newPendingDatabaseChanges.append(.saveZone(zone))
          newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
          await clearServerRecord()

        case .unknownItem:
          newPendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
          await clearServerRecord()

        case .serverRejectedRequest:
          await clearServerRecord()

        case .referenceViolation:
          guard
            let recordPrimaryKey = failedRecord.recordID.recordPrimaryKey,
            let table = tablesByName[failedRecord.recordType],
            foreignKeysByTableName[table.base.tableName]?.count == 1,
            let foreignKey = foreignKeysByTableName[table.base.tableName]?.first
          else {
            continue
          }
          func open<T>(_: some SynchronizableTable<T>) async throws {
            try await userDatabase.write { db in
              try $_isSynchronizingChanges.withValue(false) {
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
                    let recordType = try RecordType.find(T.tableName).fetchOne(db),
                    let columnInfo = recordType.tableInfo.first(where: {
                      $0.name == foreignKey.from
                    })
                  else { return }
                  let defaultValue = columnInfo.defaultValue ?? "NULL"
                  try #sql(
                    """
                    UPDATE \(T.self)
                    SET \(quote: foreignKey.from, delimiter: .identifier) = (\(raw: defaultValue))
                    WHERE (\(T.primaryKey)) = (\(bind: recordPrimaryKey))
                    """
                  )
                  .execute(db)
                  break
                case .setNull:
                  try #sql(
                    """
                    UPDATE \(T.self)
                    SET \(quote: foreignKey.from, delimiter: .identifier) = NULL
                    WHERE (\(T.primaryKey)) = (\(bind: recordPrimaryKey))
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
          await withErrorReporting(.sqliteDataCloudKitFailure) {
            try await open(table)
          }

        case .permissionFailure:
          guard
            let recordPrimaryKey = failedRecord.recordID.recordPrimaryKey,
            let table = tablesByName[failedRecord.recordType]
          else { continue }
          func open<T>(_: some SynchronizableTable<T>) async throws {
            do {
              let serverRecord = try await container.sharedCloudDatabase.record(
                for: failedRecord.recordID
              )
              await upsertFromServerRecord(serverRecord, force: true)
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
        #if canImport(FoundationModels)
          case .participantAlreadyInvited:
            continue
        #endif
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
          .find(rootRecordID)
          .update { $0.share = share }
          .execute(db)
      }
    }

    func deleteShare(shareRecordID: CKRecord.ID) async throws {
      try await userDatabase.write { db in
        let shareAndRecordNameAndZone =
          try SyncMetadata
          .where(\.isShared)
          .select { ($0.share, $0.recordName, $0.zoneName, $0.ownerName) }
          .fetchAll(db)
          .first(where: { share, _, _, _ in share?.recordID == shareRecordID }) ?? nil
        guard let (_, recordName, zoneName, ownerName) = shareAndRecordNameAndZone
        else { return }
        try SyncMetadata
          .find(
            CKRecord.ID(
              recordName: recordName,
              zoneID: CKRecordZone.ID(zoneName: zoneName, ownerName: ownerName)
            )
          )
          .update { $0.share = nil }
          .execute(db)
      }
    }

    private func upsertFromServerRecord(
      _ serverRecord: CKRecord,
      force: Bool = false
    ) async {
      await withErrorReporting(.sqliteDataCloudKitFailure) {
        try await userDatabase.write { db in
          upsertFromServerRecord(serverRecord, force: force, db: db)
        }
      }
    }

    private func upsertFromServerRecord(
      _ serverRecord: CKRecord,
      force: Bool = false,
      db: Database
    ) {
      withErrorReporting(.sqliteDataCloudKitFailure) {
        guard let recordPrimaryKey = serverRecord.recordID.recordPrimaryKey
        else { return }

        try SyncMetadata.insert {
          SyncMetadata(
            recordPrimaryKey: recordPrimaryKey,
            recordType: serverRecord.recordType,
            zoneName: serverRecord.recordID.zoneID.zoneName,
            ownerName: serverRecord.recordID.zoneID.ownerName,
            parentRecordPrimaryKey: serverRecord.parent?.recordID.recordPrimaryKey,
            parentRecordType: serverRecord.parent?.recordID.tableName,
            lastKnownServerRecord: serverRecord,
            _lastKnownServerRecordAllFields: serverRecord,
            share: nil,
            userModificationTime: serverRecord.userModificationTime
          )
        } onConflict: {
          ($0.recordPrimaryKey, $0.recordType)
        } doUpdate: {
          if tablesByName[serverRecord.recordType] == nil {
            $0.setLastKnownServerRecord(serverRecord)
          } else {
            $0.zoneName = serverRecord.recordID.zoneID.zoneName
            $0.ownerName = serverRecord.recordID.zoneID.ownerName
          }
        }
        .execute(db)

        guard
          let metadata = try SyncMetadata.find(serverRecord.recordID).fetchOne(db),
          let table = tablesByName[serverRecord.recordType]
        else {
          return
        }

        serverRecord.userModificationTime = metadata.userModificationTime

        func open<T>(_ table: some SynchronizableTable<T>) throws {
          var columnNames: [String] = T.TableColumns.writableColumns.map(\.name)
          if !force,
            let allFields = metadata._lastKnownServerRecordAllFields,
            let row = try T.find(#sql("\(bind: metadata.recordPrimaryKey)")).fetchOne(db)
          {
            serverRecord.update(
              with: allFields,
              row: T(queryOutput: row),
              columnNames: &columnNames,
              parentForeignKey: foreignKeysByTableName[T.tableName]?.count == 1
                ? foreignKeysByTableName[T.tableName]?.first
                : nil
            )
          }

          do {
            try $_currentZoneID.withValue(serverRecord.recordID.zoneID) {
              try #sql(upsert(table, record: serverRecord, columnNames: columnNames)).execute(db)
            }
            try UnsyncedRecordID.find(serverRecord.recordID).delete().execute(db)
            try SyncMetadata
              .find(serverRecord.recordID)
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
        try open(table)
      }
    }

    private func refreshLastKnownServerRecord(_ record: CKRecord) async {
      await withErrorReporting(.sqliteDataCloudKitFailure) {
        try await metadatabase.write { db in
          let metadata = try SyncMetadata.find(record.recordID).fetchOne(db)
          func updateLastKnownServerRecord() throws {
            try SyncMetadata
              .find(record.recordID)
              .update { $0.setLastKnownServerRecord(record) }
              .execute(db)
          }

          if let lastKnownDate = metadata?.lastKnownServerRecord?.modificationDate {
            if let recordDate = record.modificationDate, lastKnownDate < recordDate {
              try updateLastKnownServerRecord()
            }
          } else {
            try updateLastKnownServerRecord()
          }
        }
      }
    }

    private func updateQuery<T>(
      for _: some SynchronizableTable<T>,
      record: CKRecord,
      columnNames: some Collection<String>,
      changedColumnNames: some Collection<String>
    ) async throws -> QueryFragment {
      let nonPrimaryKeyChangedColumns =
        changedColumnNames
        .filter { $0 != T.primaryKey.name }
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
      query.append(") ON CONFLICT(\(quote: T.primaryKey.name)) DO UPDATE SET ")
      query.append(" ")
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
              return """
                \(quote: columnName) = \
                \(record.encryptedValues[columnName]?.queryFragment ?? "NULL")
                """
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
        let i = recordName.utf8.lastIndex(of: UTF8.CodeUnit(ascii: ":")),
        let j = recordName.utf8.index(i, offsetBy: 1, limitedBy: recordName.utf8.endIndex)
      else { return nil }
      let recordTypeBytes = recordName.utf8[j...]
      guard !recordTypeBytes.isEmpty else { return nil }
      return String(Substring(recordTypeBytes))
    }

    var recordPrimaryKey: String? {
      guard
        let i = recordName.utf8.lastIndex(of: UTF8.CodeUnit(ascii: ":"))
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
        || absoluteString.hasPrefix(":memory:")
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
        throw SyncEngine.SchemaError.noCloudKitContainer
      }

      let databasePath = try PragmaDatabaseList.select(\.file).fetchOne(self)
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
    package struct SchemaError: LocalizedError {
      package enum Reason {
        case cycleDetected
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
      package let reason: Reason
      package let debugDescription: String

      package var errorDescription: String? {
        "Could not synchronize data with iCloud."
      }

      static let noCloudKitContainer = Self(
        reason: .noCloudKitContainer,
        debugDescription: """
          No default CloudKit container found. Make sure to enable iCloud entitlements in your \
          app's "Signing & Capabilities" and add a container identifier.
          """
      )
    }

    fileprivate func validateSchema() throws {
      let tableNames = Set(tables.map { $0.base.tableName })
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
                Foreign key \
                \(tableName.debugDescription).\(invalidForeignKey.from.debugDescription) \
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
                Foreign key \(tableName.debugDescription).\(foreignKey.from.debugDescription) \
                action not supported. Must be 'CASCADE', 'SET DEFAULT' or 'SET NULL'.
                """
            )
          }
        }

        for table in tables {
          func open<T>(_: some SynchronizableTable<T>) throws {
            let columnsWithUniqueConstraints = try PragmaIndexList<T>
              .where { $0.isUnique && $0.origin != "pk" }
              .select(\.name)
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
          try open(table)
        }
      }
    }
  }

  package protocol SynchronizableTable<Base>: Hashable, Sendable {
    associatedtype Base: PrimaryKeyedTable & _SendableMetatype
    where
      Base.PrimaryKey.QueryOutput: IdentifierStringConvertible,
      Base.TableColumns.PrimaryColumn: WritableTableColumnExpression
    var base: Base.Type { get }
  }

  package struct SynchronizedTable<
    Base: PrimaryKeyedTable & _SendableMetatype
  >: SynchronizableTable
  where
    Base.PrimaryKey.QueryOutput: IdentifierStringConvertible,
    Base.TableColumns.PrimaryColumn: WritableTableColumnExpression
  {
    package init(for table: Base.Type = Base.self) {}
    package var base: Base.Type { Base.self }
  }

  private struct HashableSynchronizedTable: Hashable {
    let type: any SynchronizableTable
    init(_ type: any SynchronizableTable) {
      self.type = type
    }
    func hash(into hasher: inout Hasher) {
      hasher.combine(ObjectIdentifier(type.base))
    }
    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.type.base == rhs.type.base
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private func tablesByOrder(
    userDatabase: UserDatabase,
    tables: [any SynchronizableTable],
    tablesByName: [String: any SynchronizableTable]
  ) throws -> [String: Int] {
    let tableDependencies = try userDatabase.read { db in
      var dependencies: [HashableSynchronizedTable: [any SynchronizableTable]] = [:]
      for table in tables {
        func open<T>(_: some SynchronizableTable<T>) throws -> [String] {
          try PragmaForeignKeyList<T>.select(\.table)
            .fetchAll(db)
        }
        let toTables = try open(table)
        for toTable in toTables {
          guard let toTableType = tablesByName[toTable]
          else { continue }
          dependencies[HashableSynchronizedTable(table), default: []].append(toTableType)
        }
      }
      return dependencies
    }

    var visited = Set<HashableSynchronizedTable>()
    var marked = Set<HashableSynchronizedTable>()
    var result: [String: Int] = [:]
    for table in tableDependencies.keys {
      try visit(table: table)
    }
    return result

    func visit(table: HashableSynchronizedTable) throws {
      guard !visited.contains(table)
      else { return }
      guard !marked.contains(table)
      else {
        throw SyncEngine.SchemaError(
          reason: .cycleDetected,
          debugDescription: """
            Cycles are not currently permitted in schemas, e.g. a table that references itself.
            """
        )
      }

      marked.insert(table)
      for dependency in tableDependencies[table] ?? [] {
        try visit(table: HashableSynchronizedTable(dependency))
      }
      marked.remove(table)
      visited.insert(table)
      result[table.type.base.tableName] = result.count
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension Updates<SyncMetadata> {
    mutating func setLastKnownServerRecord(_ lastKnownServerRecord: CKRecord?) {
      self.zoneName = lastKnownServerRecord?.recordID.zoneID.zoneName ?? self.zoneName
      self.ownerName = lastKnownServerRecord?.recordID.zoneID.ownerName ?? self.ownerName
      self.lastKnownServerRecord = lastKnownServerRecord
      self._lastKnownServerRecordAllFields = lastKnownServerRecord
      if let lastKnownServerRecord {
        self.userModificationTime = lastKnownServerRecord.userModificationTime
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  private func upsert<T>(
    _: some SynchronizableTable<T>,
    record: CKRecord,
    columnNames: some Collection<String>
  ) -> QueryFragment {
    let allColumnNames = T.TableColumns.writableColumns.map(\.name)
    let hasNonPrimaryKeyColumns = columnNames.contains { $0 != T.primaryKey.name }
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
    query.append(") ON CONFLICT(\(quote: T.primaryKey.name)) DO")
    if hasNonPrimaryKeyColumns {
      query.append(" UPDATE SET ")
      query.append(
        columnNames
          .filter { $0 != T.primaryKey.name }
          .map {
            """
            \(quote: $0) = "excluded".\(quote: $0)
            """
          }
          .joined(separator: ", ")
      )
    } else {
      query.append(" NOTHING")
    }
    return query
  }

  @TaskLocal package var _isSynchronizingChanges = false
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @TaskLocal package var _currentZoneID: CKRecordZone.ID?
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @DatabaseFunction("sqlitedata_icloud_currentZoneName")
  func currentZoneName() -> String? {
    _currentZoneID?.zoneName
  }
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @DatabaseFunction("sqlitedata_icloud_currentOwnerName")
  func currentOwnerName() -> String? {
    _currentZoneID?.ownerName
  }

  private struct ActivityCounts {
    var sendingChangesCount = 0
    var fetchingChangesCount = 0
  }

  #if DEBUG
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    private struct NextRecordZoneChangeBatchLoggingState {
      var events: [String] = []
      var recordTypes: [String] = []
      var recordNames: [String] = []
      var tabularDescription: String? {
        guard !events.isEmpty
        else { return nil }
        var dataFrame: DataFrame = [
          "event": events,
          "recordType": recordTypes,
          "recordName": recordNames,
        ]
        dataFrame.sort(
          on: ColumnID("event", String.self),
          ColumnID("recordType", String.self),
          ColumnID("recordName", String.self)
        )
        var formattingOptions = FormattingOptions(
          maximumLineWidth: 120,
          maximumCellWidth: 80,
          maximumRowCount: 50,
          includesColumnTypes: false
        )
        formattingOptions.includesRowAndColumnCounts = false
        formattingOptions.includesRowIndices = false
        return
          dataFrame
          .description(options: formattingOptions)
          .replacing("\n", with: "\n  ")
      }
    }
  #endif
#endif
