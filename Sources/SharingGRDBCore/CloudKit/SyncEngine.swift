import CloudKit
import ConcurrencyExtras
import OSLog

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension DependencyValues {
  public var defaultSyncEngine: SyncEngine {
    get { self[SyncEngine.self] }
    set { self[SyncEngine.self] = newValue }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
public final actor SyncEngine {
  let database: any DatabaseWriter
  let logger: Logger
  lazy var metadatabase: any DatabaseWriter = try! DatabaseQueue()
  private let metadatabaseURL: URL
  let tables: [any StructuredQueriesCore.PrimaryKeyedTable.Type]
  let tablesByName: [String: any StructuredQueriesCore.PrimaryKeyedTable.Type]
  var underlyingSyncEngine: (any CKSyncEngineProtocol)!
  let defaultSyncEngine: (SyncEngine) -> any CKSyncEngineProtocol

  public init(
    container: CKContainer,
    database: any DatabaseWriter,
    logger: Logger = Logger(subsystem: "SharingGRDB", category: "CloudKit"),
    tables: [any PrimaryKeyedTable.Type]
  ) {
    self.init(
      defaultSyncEngine: { syncEngine in
        CKSyncEngine(
          CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: try? database.read { db in
              try StateSerialization.all.fetchOne(db)?.data
            },
            delegate: syncEngine
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
    defaultSyncEngine: any CKSyncEngineProtocol,
    database: any DatabaseWriter,
    metadatabaseURL: URL,
    tables: [any StructuredQueriesCore.PrimaryKeyedTable.Type]
  ) {
    self.init(
      defaultSyncEngine: { _ in defaultSyncEngine },
      database: database,
      logger: Logger(.disabled),
      metadatabaseURL: metadatabaseURL,
      tables: tables
    )
  }

  private init(
    defaultSyncEngine: @escaping (SyncEngine) -> any CKSyncEngineProtocol,
    database: any DatabaseWriter,
    logger: Logger,
    metadatabaseURL: URL,
    tables: [any StructuredQueriesCore.PrimaryKeyedTable.Type]
  ) {
    // TODO: Explain why / link to documentation?
    precondition(
      !database.configuration.foreignKeysEnabled,
      """
      Foreign key support must be disabled to synchronize with CloudKit.
      """
    )
    self.defaultSyncEngine = defaultSyncEngine
    self.database = database
    self.logger = logger
    self.metadatabaseURL = metadatabaseURL
    self.tables = tables
    self.tablesByName = Dictionary(uniqueKeysWithValues: tables.map { ($0.tableName, $0) })
    Task {
      await withErrorReporting(.sharingGRDBCloudKitFailure) {
        try await setUpSyncEngine()
      }
    }
  }

  package func setUpSyncEngine() throws {
    defer { underlyingSyncEngine = defaultSyncEngine(self) }

    metadatabase = try defaultMetadatabase
    var migrator = DatabaseMigrator()
    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif
    migrator.registerMigration("Create Metadata Tables") { db in
      try SQLQueryExpression(
        """
        CREATE TABLE "sharing_grdb_cloudkit_metadata" (
          "zoneName" TEXT NOT NULL,
          "recordName" TEXT NOT NULL,
          "lastKnownServerRecord" BLOB,
          "userModificationDate" TEXT,
          PRIMARY KEY("zoneName", "recordName")
        ) STRICT
        """
      )
      .execute(db)
      try SQLQueryExpression(
        """
        CREATE TABLE "sharing_grdb_cloudkit_zones" (
          "zoneName" TEXT PRIMARY KEY NOT NULL,
          "schema" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
      try SQLQueryExpression(
        """
        CREATE TABLE "sharing_grdb_cloudkit_stateSerialization" (
          "id" INTEGER PRIMARY KEY ON CONFLICT REPLACE CHECK ("id" = 1),
          "data" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
    }
    try migrator.migrate(metadatabase)
    let previousZones = try metadatabase.read { db in
      return try Zone.all.fetchAll(db)
    }
    let currentZones = try database.read { db in
      try SQLQueryExpression(
        """
        SELECT "name", "sql" 
        FROM "sqlite_master" 
        WHERE "type" = 'table'
        AND "name" IN (\(tablesByName.keys.map(\.queryFragment).joined(separator: ", ")))
        """,
        as: Zone.self
      )
      .fetchAll(db)
    }
    let zonesToFetch = currentZones.filter { currentZone in
      guard
        let existingZone = previousZones.first(where: { previousZone in
          currentZone.zoneName == previousZone.zoneName
        })
      else { return true }
      return existingZone.schema != currentZone.schema
    }
    if !zonesToFetch.isEmpty {
      // TODO: Should we avoid this unstructured task by making 'setUpSyncEngine' async?
      Task {
        await withErrorReporting(.sharingGRDBCloudKitFailure) {
          try await underlyingSyncEngine.fetchChanges(
            CKSyncEngine.FetchChangesOptions(
              scope: .zoneIDs(zonesToFetch.map { CKRecordZone(zoneName: $0.zoneName).zoneID })
            )
          )
          try await metadatabase.write { db in
            for zone in zonesToFetch {
              try Zone.upsert(Zone.Draft(zone)).execute(db)
            }
          }
        }
      }
    }
    try database.write { db in
      try SQLQueryExpression(
        "ATTACH DATABASE \(metadatabaseURL) AS \(quote: .sharingGRDBCloudKitSchemaName)"
      )
      .execute(db)
      db.add(function: .isUpdatingWithServerRecord)
      db.add(function: .didUpdate(syncEngine: self))
      db.add(function: .willDelete(syncEngine: self))
      for table in tables {
        func open<T: PrimaryKeyedTable>(_: T.Type) throws {
          try SQLQueryExpression(
            Trigger(on: T.self, .after, .insert, select: .didUpdate(syncEngine: self)).create
          )
          .execute(db)
          try SQLQueryExpression(
            Trigger(on: T.self, .after, .update, select: .didUpdate(syncEngine: self)).create
          )
          .execute(db)
          try SQLQueryExpression(
            Trigger(on: T.self, .before, .delete, select: .willDelete(syncEngine: self)).create
          )
          .execute(db)
          try SQLQueryExpression(
            """
            CREATE TEMPORARY TRIGGER
              "sharing_grdb_cloudkit_\(raw: T.tableName)_metadataInserts"
            AFTER INSERT ON \(T.self) FOR EACH ROW BEGIN
              INSERT INTO \(Metadata.self)
                ("zoneName", "recordName", "userModificationDate")
              SELECT
                \(quote: T.tableName, delimiter: .text),
                "new".\(quote: T.columns.primaryKey.name),
                datetime('subsec')
              ON CONFLICT("zoneName", "recordName") DO NOTHING;
            END
            """
          )
          .execute(db)
          try SQLQueryExpression(
            """
            CREATE TEMPORARY TRIGGER
              "sharing_grdb_cloudkit_\(raw: T.tableName)_metadataUpdates"
            AFTER UPDATE ON \(T.self) FOR EACH ROW BEGIN
              INSERT INTO \(Metadata.self)
                ("zoneName", "recordName")
              SELECT
                \(quote: T.tableName, delimiter: .text),
                "new".\(quote: T.columns.primaryKey.name)
              ON CONFLICT("zoneName", "recordName") DO UPDATE SET
                "userModificationDate" = datetime('subsec');
            END
            """
          )
          .execute(db)
          try SQLQueryExpression(
            """
            CREATE TEMPORARY TRIGGER
              "sharing_grdb_cloudkit_\(raw: T.tableName)_metadataDeletes"
            AFTER DELETE ON \(T.self) FOR EACH ROW BEGIN
              DELETE FROM \(Metadata.self)
              WHERE "zoneName" = \(quote: T.tableName, delimiter: .text)
              AND "recordName" = "old".\(quote: T.columns.primaryKey.name);
            END
            """
          )
          .execute(db)

          let foreignKeys = try SQLQueryExpression(
            """
            SELECT \(ForeignKey.columns) FROM pragma_foreign_key_list(\(bind: T.tableName))
            """,
            as: ForeignKey.self
          )
          .fetchAll(db)
          for foreignKey in foreignKeys {
            switch foreignKey.onDelete {
            case .cascade:
              try SQLQueryExpression(
                """
                CREATE TEMPORARY TRIGGER
                  "sharing_grdb_cloudkit_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onDeleteCascade"
                AFTER DELETE ON \(quote: foreignKey.table)
                FOR EACH ROW BEGIN
                  DELETE FROM \(table)
                  WHERE \(quote: foreignKey.from) = "old".\(quote: foreignKey.to);
                END
                """
              )
              .execute(db)

            case .restrict:
              // TODO: Report issue?
              continue

            case .setDefault:
              let defaultValue =
                try SQLQueryExpression(
                  """
                  SELECT "dflt_value"
                  FROM pragma_table_info(\(bind: T.tableName))
                  WHERE "name" = \(bind: foreignKey.from)
                  """,
                  as: String?.self
                )
                .fetchOne(db) ?? nil

              guard let defaultValue
              else {
                // TODO: Report issue?
                continue
              }
              try SQLQueryExpression(
                """
                CREATE TEMPORARY TRIGGER
                  "sharing_grdb_cloudkit_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onDeleteSetDefault"
                AFTER DELETE ON \(quote: foreignKey.table)
                FOR EACH ROW BEGIN
                  UPDATE \(table)
                  SET \(quote: foreignKey.from) = \(raw: defaultValue)
                  WHERE \(quote: foreignKey.from) = "old".\(quote: foreignKey.to);
                END
                """
              )
              .execute(db)

            case .setNull:
              try SQLQueryExpression(
                """
                CREATE TEMPORARY TRIGGER
                  "sharing_grdb_cloudkit_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onDeleteSetNull"
                AFTER DELETE ON \(quote: foreignKey.table)
                FOR EACH ROW BEGIN
                  UPDATE \(table)
                  SET \(quote: foreignKey.from) = NULL
                  WHERE \(quote: foreignKey.from) = "old".\(quote: foreignKey.to);
                END
                """
              )
              .execute(db)

            case .noAction:
              continue
            }

            switch foreignKey.onUpdate {
            case .cascade:
              try SQLQueryExpression(
                """
                CREATE TEMPORARY TRIGGER
                  "sharing_grdb_cloudkit_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onUpdateCascade"
                AFTER UPDATE ON \(quote: foreignKey.table)
                FOR EACH ROW BEGIN
                  UPDATE \(T.self)
                  SET \(quote: foreignKey.from) = "new".\(quote: foreignKey.to)
                  WHERE \(quote: foreignKey.from) = "old".\(quote: foreignKey.to);
                END
                """
              )
              .execute(db)

            case .restrict:
              // TODO: Report issue?
              continue

            case .setDefault:
              let defaultValue =
                try SQLQueryExpression(
                  """
                  SELECT "dflt_value"
                  FROM pragma_table_info(\(bind: T.tableName))
                  WHERE "name" = \(bind: foreignKey.from)
                  """,
                  as: String?.self
                )
                .fetchOne(db) ?? nil

              guard let defaultValue
              else {
                // TODO: Report issue?
                continue
              }
              try SQLQueryExpression(
                """
                CREATE TEMPORARY TRIGGER
                  "sharing_grdb_cloudkit_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onUpdateSetDefault"
                AFTER UPDATE ON \(quote: foreignKey.table)
                FOR EACH ROW BEGIN
                  UPDATE \(table)
                  SET \(quote: foreignKey.from) = \(raw: defaultValue)
                  WHERE \(quote: foreignKey.from) = "old".\(quote: foreignKey.to);
                END
                """
              )
              .execute(db)

            case .setNull:
              try SQLQueryExpression(
                """
                CREATE TEMPORARY TRIGGER
                  "sharing_grdb_cloudkit_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onUpdateSetNull"
                AFTER UPDATE ON \(quote: foreignKey.table)
                FOR EACH ROW BEGIN
                  UPDATE \(T.self)
                  SET \(quote: foreignKey.from) = NULL
                  WHERE \(quote: foreignKey.from) = "old".\(quote: foreignKey.to);
                END
                """
              )
              .execute(db)

            case .noAction:
              continue
            }
          }
        }
        try open(table)
      }
    }
  }

  package func tearDownSyncEngine() throws {
    try database.write { db in
      for table in tables {
        func open<T: PrimaryKeyedTable>(_: T.Type) throws {
          let foreignKeys = try SQLQueryExpression(
            """
            SELECT \(ForeignKey.columns) FROM pragma_foreign_key_list(\(bind: T.tableName))
            """,
            as: ForeignKey.self
          )
          .fetchAll(db)
          for foreignKey in foreignKeys {
            switch foreignKey.onDelete {
            case .cascade:
              try SQLQueryExpression(
                """
                DROP TRIGGER
                  "sharing_grdb_cloudkit_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onDeleteCascade"
                """
              )
              .execute(db)

            case .restrict:
              continue

            case .setDefault:
              try SQLQueryExpression(
                """
                DROP TRIGGER
                  "sharing_grdb_cloudkit_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onDeleteSetDefault"
                """
              )
              .execute(db)

            case .setNull:
              try SQLQueryExpression(
                """
                DROP TRIGGER
                  "sharing_grdb_cloudkit_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onDeleteSetNull"
                """
              )
              .execute(db)

            case .noAction:
              continue
            }

            switch foreignKey.onUpdate {
            case .cascade:
              try SQLQueryExpression(
                """
                DROP TRIGGER
                  "sharing_grdb_cloudkit_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onUpdateCascade"
                """
              )
              .execute(db)

            case .restrict:
              continue

            case .setDefault:
              try SQLQueryExpression(
                """
                DROP TRIGGER
                  "sharing_grdb_cloudkit_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onUpdateSetDefault"
                """
              )
              .execute(db)

            case .setNull:
              try SQLQueryExpression(
                """
                DROP TRIGGER
                  "sharing_grdb_cloudkit_\(raw: T.tableName)_belongsTo_\(raw: foreignKey.table)_onUpdateSetNull"
                """
              )
              .execute(db)

            case .noAction:
              continue
            }
          }
          try SQLQueryExpression(
            """
            DROP TRIGGER "sharing_grdb_cloudkit_\(raw: T.tableName)_metadataDeletes"
            """
          )
          .execute(db)
          try SQLQueryExpression(
            """
            DROP TRIGGER "sharing_grdb_cloudkit_\(raw: T.tableName)_metadataUpdates"
            """
          )
          .execute(db)
          try SQLQueryExpression(
            """
            DROP TRIGGER "sharing_grdb_cloudkit_\(raw: T.tableName)_metadataInserts"
            """
          )
          .execute(db)
          try SQLQueryExpression(
            Trigger(on: T.self, .before, .delete, select: .willDelete(syncEngine: self)).drop
          )
          .execute(db)
          try SQLQueryExpression(
            Trigger(on: T.self, .after, .update, select: .didUpdate(syncEngine: self)).drop
          )
          .execute(db)
          try SQLQueryExpression(
            Trigger(on: T.self, .after, .insert, select: .didUpdate(syncEngine: self)).drop
          )
          .execute(db)
        }
        try open(table)
      }
      db.remove(function: .willDelete(syncEngine: self))
      db.remove(function: .didUpdate(syncEngine: self))
      db.remove(function: .isUpdatingWithServerRecord)
    }
    try database.writeWithoutTransaction { db in
      try SQLQueryExpression(
        "DETACH DATABASE \(quote: .sharingGRDBCloudKitSchemaName)"
      )
      .execute(db)
    }
    try metadatabase.close()
    try FileManager.default.removeItem(at: metadatabaseURL)
  }

  public func fetchChanges() async throws {
    try await underlyingSyncEngine.fetchChanges()
  }

  public func deleteLocalData() throws {
    withErrorReporting(.sharingGRDBCloudKitFailure) {
      try database.write { db in
        for table in tables {
          func open<T: PrimaryKeyedTable>(_: T.Type) {
            withErrorReporting(.sharingGRDBCloudKitFailure) {
              try T.delete().execute(db)
            }
          }
          open(table)
        }
      }
    }
    try tearDownSyncEngine()
    try setUpSyncEngine()
  }

  func didUpdate(recordName: String, zoneName: String) {
    underlyingSyncEngine.state.add(
      pendingRecordZoneChanges: [
        .saveRecord(
          CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone(zoneName: zoneName).zoneID
          )
        )
      ]
    )
  }

  func willDelete(recordName: String, zoneName: String) {
    underlyingSyncEngine.state.add(
      pendingRecordZoneChanges: [
        .deleteRecord(
          CKRecord.ID(
            recordName: recordName,
            zoneID: CKRecordZone(zoneName: zoneName).zoneID
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
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngine: CKSyncEngineDelegate {
  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    logger.log(event)

    switch event {
    case .accountChange(let event):
      handleAccountChange(event)
    case .stateUpdate(let event):
      handleStateUpdate(event)
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
      handleSentRecordZoneChanges(event)
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
    let changes = syncEngine.state.pendingRecordZoneChanges.filter(context.options.scope.contains)
    guard !changes.isEmpty
    else { return nil }

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
          nextRecordZoneChangeBatch: \(context.reason)
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

      let metadata = await metadataFor(recordID: recordID)
      guard let table = tablesByName[recordID.zoneID.zoneName]
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
          metadata?.lastKnownServerRecord
          ?? CKRecord(
            recordType: recordID.zoneID.zoneName,
            recordID: recordID
          )
        record.update(
          with: T(queryOutput: row),
          userModificationDate: metadata?.userModificationDate
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
      for table in tables {
        underlyingSyncEngine.state.add(
          pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneName: table.tableName))]
        )
        withErrorReporting(.sharingGRDBCloudKitFailure) {
          let names: [String] = try database.read { db in
            func open<T: PrimaryKeyedTable>(_: T.Type) throws -> [String] {
              try T
                .select { SQLQueryExpression("\($0.primaryKey)", as: String.self) }
                .fetchAll(db)
            }
            return try open(table)
          }
          underlyingSyncEngine.state.add(
            pendingRecordZoneChanges: names.map {
              .saveRecord(
                CKRecord.ID(
                  recordName: $0,
                  zoneID: CKRecordZone(zoneName: table.tableName).zoneID
                )
              )
            }
          )
        }
      }
    case .signOut, .switchAccounts:
      withErrorReporting(.sharingGRDBCloudKitFailure) {
        try deleteLocalData()
      }
    @unknown default:
      break
    }
  }

  private func handleStateUpdate(_ event: CKSyncEngine.Event.StateUpdate) {
    withErrorReporting(.sharingGRDBCloudKitFailure) {
      try database.write { db in
        try StateSerialization.insert(
          StateSerialization(data: event.stateSerialization)
        )
        .execute(db)
      }
    }
  }

  private func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) {
    withErrorReporting(.sharingGRDBCloudKitFailure) {
      try database.write { db in
        for deletion in event.deletions {
          if let table = tablesByName[deletion.zoneID.zoneName] {
            func open<T: PrimaryKeyedTable>(_: T.Type) {
              withErrorReporting(.sharingGRDBCloudKitFailure) {
                try T.delete().execute(db)
              }
            }
            open(table)
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
  ) {
    for modifiedRecord in modifications {
      mergeFromServerRecord(modifiedRecord)
      refreshLastKnownServerRecord(modifiedRecord)
    }

    $isUpdatingWithServerRecord.withValue(true) {
      for (recordID, _) in deletions {
        if let table = tablesByName[recordID.zoneID.zoneName] {
          func open<T: PrimaryKeyedTable>(_: T.Type) {
            withErrorReporting(.sharingGRDBCloudKitFailure) {
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
            .sharingGRDBCloudKitFailure.appending(
            """
            : No table to delete from: "\(recordID.zoneID.zoneName)"
            """
            )
          )
        }
      }
    }
  }

  private func handleSentRecordZoneChanges(_ event: CKSyncEngine.Event.SentRecordZoneChanges) {
    for savedRecord in event.savedRecords {
      refreshLastKnownServerRecord(savedRecord)
    }

    var newPendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] = []
    var newPendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
    defer {
      underlyingSyncEngine.state.add(pendingDatabaseChanges: newPendingDatabaseChanges)
      underlyingSyncEngine.state.add(pendingRecordZoneChanges: newPendingRecordZoneChanges)
    }
    for failedRecordSave in event.failedRecordSaves {
      let failedRecord = failedRecordSave.record

      func clearServerRecord() {
        withErrorReporting {
          try database.write { db in
            try Metadata
              .find(recordID: failedRecord.recordID)
              .update { $0.lastKnownServerRecord = nil }
              .execute(db)
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
        newPendingDatabaseChanges.append(.saveZone(zone))
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
  }

  private func mergeFromServerRecord(_ record: CKRecord) {
    withErrorReporting(.sharingGRDBCloudKitFailure) {
      let userModificationDate =
        try metadatabase.read { db in
          try Metadata.find(recordID: record.recordID).select(\.userModificationDate).fetchOne(db)
        }
        ?? nil
      guard let table = tablesByName[record.recordID.zoneID.zoneName]
      else {
        reportIssue(
          .sharingGRDBCloudKitFailure.appending(
            """
            : No table to merge from: "\(record.recordID.zoneID.zoneName)"
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
          try $isUpdatingWithServerRecord.withValue(true) {
            try SQLQueryExpression(query).execute(db)
            try Metadata
              .insert(Metadata(record: record)) {
                $0.lastKnownServerRecord = record
                $0.userModificationDate = record.userModificationDate
              }
              .execute(db)
          }
        }
        return
      }
    }
  }

  private func refreshLastKnownServerRecord(_ record: CKRecord) {
    let metadata = metadataFor(recordID: record.recordID)

    func updateLastKnownServerRecord() {
      withErrorReporting(.sharingGRDBCloudKitFailure) {
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

  private func metadataFor(recordID: CKRecord.ID) -> Metadata? {
    withErrorReporting(.sharingGRDBCloudKitFailure) {
      try metadatabase.read { db in
        try Metadata.find(recordID: recordID).fetchOne(db)
      }
    }
      ?? nil
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngine: TestDependencyKey {
  public static var testValue: SyncEngine {
    SyncEngine(container: .default(), database: try! DatabaseQueue(), tables: [])
  }
}

@available(macOS 14, iOS 17, tvOS 17, watchOS 10, *)
extension DatabaseFunction {
  fileprivate static func didUpdate(syncEngine: SyncEngine) -> Self {
    Self("didUpdate") {
      await syncEngine.didUpdate(recordName: $0, zoneName: $1)
    }
  }

  fileprivate static func willDelete(syncEngine: SyncEngine) -> Self {
    return Self("willDelete") {
      await syncEngine.willDelete(recordName: $0, zoneName: $1)
    }
  }

  fileprivate static var isUpdatingWithServerRecord: Self {
    Self("isUpdatingWithServerRecord", argumentCount: 0) { _ in
      SharingGRDBCore.isUpdatingWithServerRecord
    }
  }

  private convenience init(
    _ name: String,
    function: @escaping @Sendable (String, String) async -> Void
  ) {
    self.init(name, argumentCount: 2) { arguments in
      guard
        let tableName = String.fromDatabaseValue(arguments[0]),
        let id = String.fromDatabaseValue(arguments[1])
      else {
        return nil
      }
      Task { await function(tableName, id) }
      return nil
    }
  }
}

private struct ForeignKey: QueryDecodable, QueryRepresentable {
  enum Action: String, QueryBindable {
    case cascade = "CASCADE"
    case restrict = "RESTRICT"
    case setDefault = "SET DEFAULT"
    case setNull = "SET NULL"
    case noAction = "NO ACTION"
  }

  typealias QueryValue = Self

  let table: String
  let from: String
  let to: String
  let onUpdate: Action
  let onDelete: Action

  init(decoder: inout some QueryDecoder) throws {
    guard
      let table = try decoder.decode(String.self),
      let from = try decoder.decode(String.self),
      let to = try decoder.decode(String.self),
      let onUpdate = try decoder.decode(Action.self),
      let onDelete = try decoder.decode(Action.self)
    else {
      throw QueryDecodingError.missingRequiredColumn
    }
    self.table = table
    self.from = from
    self.to = to
    self.onUpdate = onUpdate
    self.onDelete = onDelete
  }

  static var columns: QueryFragment {
    """
    "table", "from", "to", "on_update", "on_delete"
    """
  }
}

@TaskLocal private var isUpdatingWithServerRecord = false

private struct Trigger<Base: PrimaryKeyedTable> {
  typealias QueryValue = Void

  let function: DatabaseFunction
  let operation: Operation
  let when: When

  init(on _: Base.Type, _ when: When, _ operation: Operation, select function: DatabaseFunction) {
    self.function = function
    self.operation = operation
    self.when = when
  }

  var name: QueryFragment {
    "\(quote: "sharing_grdb_cloudkit_\(operation.rawValue.string.lowercased())_\(Base.tableName)")"
  }

  var create: QueryFragment {
    """
    CREATE TEMPORARY TRIGGER \(name)
    \(when.rawValue) \(operation.rawValue) ON \(quote: Base.tableName) FOR EACH ROW BEGIN
      SELECT \(raw: function.name)(
        \(quote: operation == .delete ? "old" : "new").\(quote: Base.columns.primaryKey.name),
        \(quote: Base.tableName, delimiter: .text)
      )
      WHERE NOT isUpdatingWithServerRecord();
    END
    """
  }

  var drop: QueryFragment {
    "DROP TRIGGER \(name)"
  }

  enum Operation: QueryFragment {
    case insert = "INSERT"
    case update = "UPDATE"
    case delete = "DELETE"
  }

  enum When: QueryFragment {
    case before = "BEFORE"
    case after = "AFTER"
  }
}

extension __CKRecordObjCValue {
  fileprivate var queryFragment: QueryFragment {
    if let value = self as? Int64 {
      return value.queryFragment
    } else if let value = self as? Double {
      return value.queryFragment
    } else if let value = self as? String {
      return value.queryFragment
    } else if let value = self as? Data {
      return value.queryFragment
    } else if let value = self as? Date {
      return value.queryFragment
    } else {
      return "\(.invalid(Unbindable()))"
    }
  }
}

private struct Unbindable: Error {}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension Metadata {
  package static func find(recordID: CKRecord.ID) -> Where<Self> {
    Self.where {
      $0.zoneName.eq(recordID.zoneID.zoneName)
        && $0.recordName.eq(recordID.recordName)
    }
  }

  init(record: CKRecord) {
    self.init(
      zoneName: record.recordID.zoneID.zoneName,
      recordName: record.recordID.recordName,
      lastKnownServerRecord: record,
      userModificationDate: record.userModificationDate
    )
  }
}

extension String {
  fileprivate static let sharingGRDBCloudKitSchemaName = "sharing_grdb_icloud"
  fileprivate static let sharingGRDBCloudKitFailure = "SharingGRDB CloudKit Failure"
}

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
extension DatabaseWriter where Self == DatabasePool {
  init(container: CKContainer) throws {
    let path = URL.metadatabase(container: container).path(percentEncoded: false)
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.trace {
        logger.debug("\($0.expandedDescription)")
      }
    }
    logger.debug(
      """
      SharingGRDB: Metadatabase connection:
      open "\(path)"
      """
    )
    try FileManager.default.createDirectory(
      at: .applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    try self.init(
      path: path,
      configuration: configuration
    )
  }
}

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
extension URL {
  fileprivate static func metadatabase(container: CKContainer) -> Self {
    applicationSupportDirectory.appending(
      component: "\(container.containerIdentifier.map { "\($0)." } ?? "")sharing-grdb-icloud.sqlite"
    )
  }
}

@available(iOS 14, macOS 11, tvOS 14, watchOS 7, *)
private let logger = Logger(subsystem: "SharingGRDB", category: "CloudKit")

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension Logger {
  func log(_ event: CKSyncEngine.Event) {
    let prefix = "handleEvent:"
    switch event {
    case .stateUpdate:
      debug("\(prefix) stateUpdate")
    case .accountChange(let event):
      switch event.changeType {
      case .signIn(let currentUser):
        debug(
          """
          \(prefix) signIn
            Current user: \(currentUser.recordName).\(currentUser.zoneID.ownerName).\(currentUser.zoneID.zoneName)
          """
        )
      case .signOut(let previousUser):
        debug(
          """
          \(prefix) signOut
            Previous user: \(previousUser.recordName).\(previousUser.zoneID.ownerName).\(previousUser.zoneID.zoneName)
          """
        )
      case .switchAccounts(let previousUser, let currentUser):
        debug(
          """
          \(prefix) switchAccounts:
            Previous user: \(previousUser.recordName).\(previousUser.zoneID.ownerName).\(previousUser.zoneID.zoneName)
            Current user:  \(currentUser.recordName).\(currentUser.zoneID.ownerName).\(currentUser.zoneID.zoneName)
          """
        )
      @unknown default:
        debug("unknown")
      }
    case .fetchedDatabaseChanges(let event):
      let deletions =
        event.deletions.isEmpty
        ? "⚪️ No deletions"
        : "✅ Zones deleted (\(event.deletions.count): "
          + event.deletions
          .map { $0.zoneID.zoneName }
          .sorted()
          .joined(separator: ", ")
      debug(
        """
        \(prefix) fetchedDatabaseChanges
          \(deletions)
        """
      )
    case .fetchedRecordZoneChanges(let event):
      let deletionsByZoneName = Dictionary(
        grouping: event.deletions,
        by: \.recordID.zoneID.zoneName
      )
      let zoneDeletions = deletionsByZoneName.keys.sorted()
        .map { zoneName in "\(zoneName) (\(deletionsByZoneName[zoneName]!.count))" }
        .joined(separator: ", ")
      let deletions =
        event.deletions.isEmpty
        ? "⚪️ No deletions" : "✅ Records deleted (\(event.deletions.count)): \(zoneDeletions)"

      let modificationsByZoneName = Dictionary(
        grouping: event.modifications,
        by: \.record.recordID.zoneID.zoneName
      )
      let zoneModifications = modificationsByZoneName.keys.sorted()
        .map { zoneName in "\(zoneName) (\(modificationsByZoneName[zoneName]!.count))" }
        .joined(separator: ", ")
      let modifications =
        event.modifications.isEmpty
        ? "⚪️ No modifications"
        : "✅ Records modified (\(event.modifications.count)): \(zoneModifications)"

      debug(
        """
        \(prefix) fetchedRecordZoneChanges
          \(modifications)
          \(deletions)
        """
      )
    case .sentDatabaseChanges(let event):
      let savedZoneNames = event.savedZones
        .map { $0.zoneID.zoneName }
        .sorted()
        .joined(separator: ", ")
      let savedZones =
        event.savedZones.isEmpty
        ? "⚪️ No saved zones" : "✅ Saved zones (\(event.savedZones.count)): \(savedZoneNames)"

      let deletedZoneNames = event.deletedZoneIDs
        .map { $0.zoneName }
        .sorted()
        .joined(separator: ", ")
      let deletedZones =
        event.deletedZoneIDs.isEmpty
        ? "⚪️ No deleted zones"
        : "✅ Deleted zones (\(event.deletedZoneIDs.count)): \(deletedZoneNames)"

      let failedZoneSaveNames = event.failedZoneSaves
        .map { $0.zone.zoneID.zoneName }
        .sorted()
        .joined(separator: ", ")
      let failedZoneSaves =
        event.failedZoneSaves.isEmpty
        ? "⚪️ No failed saved zones"
        : "🛑 Failed zone saves (\(event.failedZoneSaves.count)): \(failedZoneSaveNames)"

      let failedZoneDeleteNames = event.failedZoneDeletes
        .keys
        .map { $0.zoneName }
        .sorted()
        .joined(separator: ", ")
      let failedZoneDeletes =
      event.failedZoneDeletes.isEmpty
      ? "⚪️ No failed deleted zones"
      : "🛑 Failed zone delete (\(event.failedZoneDeletes.count)): \(failedZoneDeleteNames)"

      debug(
        """
        \(prefix) sentDatabaseChanges
          \(savedZones)
          \(deletedZones) 
          \(failedZoneSaves)
          \(failedZoneDeletes)
        """
      )
    case .sentRecordZoneChanges(let event):
      let savedRecordsByZoneName = Dictionary(
        grouping: event.savedRecords,
        by: \.recordID.zoneID.zoneName
      )
      let savedRecords = savedRecordsByZoneName.keys
        .sorted()
        .map { "\($0) (\(savedRecordsByZoneName[$0]!.count))" }
        .joined(separator: ", ")

      let deletedRecordsByZoneName = Dictionary(
        grouping: event.deletedRecordIDs,
        by: \.zoneID.zoneName
      )
      let deletedRecords = deletedRecordsByZoneName.keys
        .sorted()
        .map { "\($0) (\(deletedRecordsByZoneName[$0]!.count))" }
        .joined(separator: ", ")

      let failedRecordSavesByZoneName = Dictionary(
        grouping: event.failedRecordSaves,
        by: \.record.recordID.zoneID.zoneName
      )
      let failedRecordSaves = failedRecordSavesByZoneName.keys
        .sorted()
        .map { "\($0) (\(failedRecordSavesByZoneName[$0]!.count))" }
        .joined(separator: ", ")

      let failedRecordDeletesByZoneName = Dictionary(
        grouping: event.failedRecordDeletes.keys,
        by: \.zoneID.zoneName
      )
      let failedRecordDeletes = failedRecordDeletesByZoneName.keys
        .sorted()
        .map { "\($0) (\(failedRecordDeletesByZoneName[$0]!.count))" }
        .joined(separator: ", ")

      debug(
        """
        \(prefix) sentRecordZoneChanges
          \(savedRecordsByZoneName.isEmpty ? "⚪️ No records saved" : "✅ Saved records: \(savedRecords)")
          \(deletedRecordsByZoneName.isEmpty ? "⚪️ No records deleted" : "✅ Deleted records: \(deletedRecords)")
          \(failedRecordSavesByZoneName.isEmpty ? "⚪️ No records failed save" : "🛑 Records failed save: \(failedRecordSaves)")
          \(failedRecordDeletesByZoneName.isEmpty ? "⚪️ No records failed delete" : "🛑 Records failed delete: \(failedRecordDeletes)")
        """
      )
    case .willFetchChanges(let event):
      if #available(macOS 14.2, iOS 17.2, tvOS 17.2, watchOS 10.2, *) {
        debug("\(prefix) willFetchChanges: \(event.context.reason.description)")
      } else {
        debug("\(prefix) willFetchChanges")
      }
    case .willFetchRecordZoneChanges(let event):
      debug("\(prefix) willFetchRecordZoneChanges: \(event.zoneID.zoneName)")
    case .didFetchRecordZoneChanges(let event):
      let errorType = event.error.map {
        switch $0.code {
        case .internalError: "internalError"
        case .partialFailure: "partialFailure"
        case .networkUnavailable: "networkUnavailable"
        case .networkFailure: "networkFailure"
        case .badContainer: "badContainer"
        case .serviceUnavailable: "serviceUnavailable"
        case .requestRateLimited: "requestRateLimited"
        case .missingEntitlement: "missingEntitlement"
        case .notAuthenticated: "notAuthenticated"
        case .permissionFailure: "permissionFailure"
        case .unknownItem: "unknownItem"
        case .invalidArguments: "invalidArguments"
        case .resultsTruncated: "resultsTruncated"
        case .serverRecordChanged: "serverRecordChanged"
        case .serverRejectedRequest: "serverRejectedRequest"
        case .assetFileNotFound: "assetFileNotFound"
        case .assetFileModified: "assetFileModified"
        case .incompatibleVersion: "incompatibleVersion"
        case .constraintViolation: "constraintViolation"
        case .operationCancelled: "operationCancelled"
        case .changeTokenExpired: "changeTokenExpired"
        case .batchRequestFailed: "batchRequestFailed"
        case .zoneBusy: "zoneBusy"
        case .badDatabase: "badDatabase"
        case .quotaExceeded: "quotaExceeded"
        case .zoneNotFound: "zoneNotFound"
        case .limitExceeded: "limitExceeded"
        case .userDeletedZone: "userDeletedZone"
        case .tooManyParticipants: "tooManyParticipants"
        case .alreadyShared: "alreadyShared"
        case .referenceViolation: "referenceViolation"
        case .managedAccountRestricted: "managedAccountRestricted"
        case .participantMayNeedVerification: "participantMayNeedVerification"
        case .serverResponseLost: "serverResponseLost"
        case .assetNotAvailable: "assetNotAvailable"
        case .accountTemporarilyUnavailable: "accountTemporarilyUnavailable"
        @unknown default: "unknown"
        }
      }
      let error = errorType.map { "\n  ❌ \($0)" } ?? ""
      debug(
        """
        \(prefix) willFetchRecordZoneChanges
          ✅ Zone: \(event.zoneID.zoneName)\(error)
        """
      )
    case .didFetchChanges(let event):
      if #available(macOS 14.2, iOS 17.2, tvOS 17.2, watchOS 10.2, *) {
        debug("\(prefix) didFetchChanges: \(event.context.reason.description)")
      } else {
        debug("\(prefix) didFetchChanges")
      }
    case .willSendChanges(let event):
      debug("\(prefix) willSendChanges: \(event.context.reason.description)")
    case .didSendChanges(let event):
      debug("\(prefix) didSendChanges: \(event.context.reason.description)")
    @unknown default:
      warning("\(prefix) ⚠️ unknown event: \(event.description)")
    }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package protocol CKSyncEngineProtocol<State>: Sendable {
  associatedtype State: CKSyncEngineStateProtocol
  func fetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws
  var state: State { get }
}
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngineProtocol {
  package func fetchChanges() async throws {
    try await fetchChanges(CKSyncEngine.FetchChangesOptions())
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package protocol CKSyncEngineStateProtocol: Sendable {
  func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
  func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
  func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
  func remove(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngine: CKSyncEngineProtocol {
}
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngine.State: CKSyncEngineStateProtocol {
}
