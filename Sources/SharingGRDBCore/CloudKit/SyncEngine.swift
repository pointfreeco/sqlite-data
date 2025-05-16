import CloudKit
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
  nonisolated let container: CKContainer
  nonisolated let database: any DatabaseWriter
  nonisolated let tables: [String: any StructuredQueriesCore.PrimaryKeyedTable.Type]
  lazy var metadatabase: any DatabaseWriter = try! DatabaseQueue()
  var stateSerialization: CKSyncEngine.State.Serialization?
  lazy var underlyingSyncEngine: CKSyncEngine = defaultSyncEngine

  public init(
    container: CKContainer,
    database: any DatabaseWriter,
    tables: [any StructuredQueriesCore.PrimaryKeyedTable.Type]
  ) {
    // TODO: Explain why / link to documentation?
    precondition(
      !database.configuration.foreignKeysEnabled,
      """
      Foreign key support must be disabled to synchronize with CloudKit.
      """
    )
    self.container = container
    self.database = database
    self.tables = Dictionary(uniqueKeysWithValues: tables.map { ($0.tableName, $0) })
    Task {
      await withErrorReporting(.sharingGRDBCloudKitFailure) {
        try await setUpSyncEngine()
      }
    }
  }

  func setUpSyncEngine() throws {
    defer { underlyingSyncEngine = defaultSyncEngine }

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
      stateSerialization = try StateSerialization.all.fetchOne(db)?.data
      return try Zone.all.fetchAll(db)
    }
    let currentZones = try database.read { db in
      try SQLQueryExpression(
        """
        SELECT "name", "sql" 
        FROM "sqlite_master" 
        WHERE "type" = 'table'
        AND "name" IN (\(tables.keys.map(\.queryFragment).joined(separator: ", ")))
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
      db.add(function: .areTriggersEnabled)
      db.add(function: .didUpdate)
      db.add(function: .willDelete)
      for table in tables.values {
        func open<T: PrimaryKeyedTable>(_: T.Type) throws {
          try SQLQueryExpression(
            Trigger(on: T.self, .after, .insert, select: .didUpdate).create
          )
          .execute(db)
          try SQLQueryExpression(
            Trigger(on: T.self, .after, .update, select: .didUpdate).create
          )
          .execute(db)
          try SQLQueryExpression(
            Trigger(on: T.self, .before, .delete, select: .willDelete).create
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
                '\(raw: table.tableName)',
                "new".\(quote: T.columns.primaryKey.name),
                datetime('subsec')
              WHERE areTriggersEnabled()
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
              SELECT '\(raw: table.tableName)', "new".\(quote: T.columns.primaryKey.name)
              WHERE areTriggersEnabled()
              ON CONFLICT("zoneName", "recordName") DO UPDATE SET
                "userModificationDate" = datetime('subsec');
            END
            """
          )
          .execute(db)
          let foreignKeys = try SQLQueryExpression(
            """
            SELECT \(ForeignKey.columns) FROM pragma_foreign_key_list(\(bind: table.tableName))
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
              // TODO: Report issue?
              continue

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
              // TODO: Report issue?
              continue

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

  func tearDownSyncEngine() throws {
    try database.write { db in
      for table in tables.values {
        func open<T: PrimaryKeyedTable>(_: T.Type) throws {
          let foreignKeys = try SQLQueryExpression(
            """
            SELECT \(ForeignKey.columns) FROM pragma_foreign_key_list(\(bind: table.tableName))
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
              continue

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

            switch foreignKey.onDelete {
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
              continue

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
            DROP TRIGGER "sharing_grdb_cloudkit_\(raw: table.tableName)_metadataUpdates"
            """
          )
          .execute(db)
          try SQLQueryExpression(
            """
            DROP TRIGGER "sharing_grdb_cloudkit_\(raw: table.tableName)_metadataInserts"
            """
          )
          .execute(db)
          try SQLQueryExpression(
            Trigger(on: T.self, .before, .delete, select: .willDelete).drop
          )
          .execute(db)
          try SQLQueryExpression(
            Trigger(on: T.self, .after, .update, select: .didUpdate).drop
          )
          .execute(db)
          try SQLQueryExpression(
            Trigger(on: T.self, .after, .insert, select: .didUpdate).drop
          )
          .execute(db)
        }
        try open(table)
      }
      db.remove(function: .willDelete)
      db.remove(function: .didUpdate)
      db.remove(function: .areTriggersEnabled)
    }
    try database.write { db in
      try SQLQueryExpression(
        "DETACH DATABASE \(quote: .sharingGRDBCloudKitSchemaName)"
      )
      .execute(db)
    }
    try FileManager.default.removeItem(at: metadatabaseURL)
  }

  public func deleteLocalData() throws {
    withErrorReporting(.sharingGRDBCloudKitFailure) {
      try database.write { db in
        for table in tables.values {
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

  private var metadatabaseURL: URL {
    URL.metadatabase(container: container)
  }

  private var defaultMetadatabase: any DatabaseWriter {
    get throws {
      var configuration = Configuration()
      configuration.prepareDatabase { db in
        db.trace {
          logger.debug("\($0.expandedDescription)")
        }
      }
      logger.info(
        """
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

  private var defaultSyncEngine: CKSyncEngine {
    CKSyncEngine(
      CKSyncEngine.Configuration(
        database: container.privateCloudDatabase,
        stateSerialization: stateSerialization,
        delegate: self
      )
    )
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngine: CKSyncEngineDelegate {
  public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    logger.debug("handleEvent: \(event)")

    switch event {
    case .accountChange(let event):
      handleAccountChange(event)
    case .stateUpdate(let event):
      stateSerialization = event.stateSerialization
      withErrorReporting(.sharingGRDBCloudKitFailure) {
        try database.write { db in
          try StateSerialization.insert(
            StateSerialization(data: event.stateSerialization)
          )
          .execute(db)
        }
      }
    case .fetchedDatabaseChanges(let event):
      handleFetchedDatabaseChanges(event)
    case .sentDatabaseChanges:
      break
    case .fetchedRecordZoneChanges(let event):
      handleFetchedRecordZoneChanges(event)
    case .sentRecordZoneChanges(let event):
      handleSentRecordZoneChanges(event)
    case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .willFetchChanges,
      .didFetchChanges, .willSendChanges, .didSendChanges:
      break
    @unknown default:
      logger.warning("Sync engine received unknown event: \(event)")
    }
  }

  public func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    logger.debug("nextRecordZoneChangeBatch: \(context)")

    let changes = syncEngine.state.pendingRecordZoneChanges.filter(context.options.scope.contains)
    let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
      let record = await lastKnownServerRecord(recordID: recordID)
      guard let table = tables[recordID.zoneID.zoneName]
      else {
        reportIssue("")
        syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
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
          return nil
        }

        let ckRecord =
          record?.lastKnownServerRecord
          ?? CKRecord(
            recordType: recordID.zoneID.zoneName,
            recordID: recordID
          )
        ckRecord.update(
          with: T(queryOutput: row),
          userModificationDate: record?.userModificationDate
        )
        await refreshLastKnownServerRecord(ckRecord)
        return ckRecord
      }
      return await open(table)
    }
    return batch
  }

  private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
    switch event.changeType {
    case .signIn:
      for table in tables.values {
        underlyingSyncEngine.state.add(
          pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneName: table.tableName))]
        )
        withErrorReporting(.sharingGRDBCloudKitFailure) {
          // TODO: Should this work be batched?
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

  private func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) {
    withErrorReporting(.sharingGRDBCloudKitFailure) {
      try database.write { db in
        for deletion in event.deletions {
          if let table = tables[deletion.zoneID.zoneName] {
            func open<T: PrimaryKeyedTable>(_: T.Type) {
              withErrorReporting(.sharingGRDBCloudKitFailure) {
                try T.delete().execute(db)
              }
            }
            open(table)
          }
        }
      }
    }
  }

  private func handleFetchedRecordZoneChanges(
    _ event: CKSyncEngine.Event.FetchedRecordZoneChanges
  ) {
    for modification in event.modifications {
      mergeFromServerRecord(modification.record)
      refreshLastKnownServerRecord(modification.record)
    }

    for deletion in event.deletions {
      if let table = tables[deletion.recordID.zoneID.zoneName] {
        func open<T: PrimaryKeyedTable>(_: T.Type) {
          withErrorReporting(.sharingGRDBCloudKitFailure) {
            try database.write { db in
              try T.find(recordID: deletion.recordID)
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
            : No table to delete from: "\(deletion.recordID.zoneID.zoneName)"
            """
          )
        )
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
        .operationCancelled:
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
      guard let table = tables[record.recordID.zoneID.zoneName]
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
          try $areTriggersEnabled.withValue(false) {
            try SQLQueryExpression(query).execute(db)
          }
        }
        return
      }
    }
  }

  private func refreshLastKnownServerRecord(_ record: CKRecord) {
    let localRecord = lastKnownServerRecord(recordID: record.recordID)

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

    if let lastKnownDate = localRecord?.lastKnownServerRecord?.modificationDate {
      if let recordDate = record.modificationDate, lastKnownDate < recordDate {
        updateLastKnownServerRecord()
      }
    } else {
      updateLastKnownServerRecord()
    }
  }

  private func lastKnownServerRecord(recordID: CKRecord.ID) -> Metadata? {
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
  fileprivate static var didUpdate: Self {
    Self("didUpdate") {
      @Dependency(\.defaultSyncEngine) var syncEngine
      await syncEngine.didUpdate(recordName: $0, zoneName: $1)
    }
  }

  fileprivate static var willDelete: Self {
    Self("willDelete") {
      @Dependency(\.defaultSyncEngine) var syncEngine
      await syncEngine.willDelete(recordName: $0, zoneName: $1)
    }
  }

  fileprivate static var areTriggersEnabled: Self {
    Self("areTriggersEnabled", argumentCount: 0) { _ in
      SharingGRDBCore.areTriggersEnabled
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

@TaskLocal private var areTriggersEnabled = true

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
      WHERE areTriggersEnabled();
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
  static func find(recordID: CKRecord.ID) -> Where<Self> {
    Self.where {
      $0.zoneName.eq(recordID.zoneID.zoneName)
        && $0.recordName.eq(recordID.recordName)
    }
  }
}

extension String {
  fileprivate static let sharingGRDBCloudKitSchemaName = "sharing_grdb_icloud"
  fileprivate static let sharingGRDBCloudKitFailure = "SharingGRDB CloudKit Failure"
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
