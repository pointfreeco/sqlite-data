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
  var stateSerialization: CKSyncEngine.State.Serialization?
  lazy var underlyingSyncEngine: CKSyncEngine = defaultSyncEngine

  public init(
    container: CKContainer,
    database: any DatabaseWriter,
    tables: [any StructuredQueriesCore.PrimaryKeyedTable.Type]
  ) {
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
    let metadatabaseURL = try URL.metadatabase(container: container)
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.trace {
        logger.debug("\($0.expandedDescription)")
      }
    }
    let metadatabase = try DatabaseQueue(
      path: metadatabaseURL.path(percentEncoded: false),
      configuration: configuration
    )
    logger.info(
      """
      open "\(metadatabaseURL.path(percentEncoded: false))"
      """
    )
    var migrator = DatabaseMigrator()
    #if DEBUG
      migrator.eraseDatabaseOnSchemaChange = true
    #endif
    migrator.registerMigration("Create Metadata Tables") { db in
      try SQLQueryExpression(
        """
        CREATE TABLE "sharing_grdb_cloudkit_records" (
          "zoneName" TEXT NOT NULL,
          "recordName" TEXT NOT NULL,
          "lastKnownServerRecord" BLOB,
          "localModificationDate" TEXT NOT NULL,
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
    stateSerialization = try metadatabase.read { db in
      try StateSerialization.all.fetchOne(db)?.data
    }
    let previousZones = try metadatabase.read { db in
      try Zone.all.fetchAll(db)
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
      db.add(function: .didInsert)
      db.add(function: .didUpdate)
      db.add(function: .willDelete)
      for table in tables.values {
        func open<T: PrimaryKeyedTable>(_: T.Type) throws {
          try SQLQueryExpression(
            Trigger(on: T.self, .after, .insert, select: .didInsert).create
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
              "sharing_grdb_cloudkit_\(raw: T.tableName)_localModifications"
            AFTER UPDATE ON \(T.self) FOR EACH ROW BEGIN
              INSERT INTO \(Record.self)
                ("zoneName", "recordName", "localModificationDate")
              VALUES 
                (
                  '\(raw: table.tableName)',
                  "new".\(quote: T.columns.primaryKey.name),
                  datetime('subsec')
                )
              ON CONFLICT("zoneName", "recordName") DO UPDATE SET
                "localModificationDate" = "excluded"."localModificationDate";
            END
            """
          )
          .execute(db)
        }
        try open(table)
      }
    }
  }

  func tearDownSyncEngine() throws {
    try database.write { db in
      for table in tables.values {
        try SQLQueryExpression(
          """
          DROP TRIGGER "sharing_grdb_cloudkit_\(raw: table.tableName)_localModifications"
          """
        )
        .execute(db)
        func open<T: PrimaryKeyedTable>(_: T.Type) throws {
          try SQLQueryExpression(
            Trigger(on: T.self, .before, .delete, select: .willDelete).drop
          )
          .execute(db)
          try SQLQueryExpression(
            Trigger(on: T.self, .after, .update, select: .didUpdate).drop
          )
          .execute(db)
          try SQLQueryExpression(
            Trigger(on: T.self, .after, .insert, select: .didInsert).drop
          )
          .execute(db)
        }
        try open(table)
      }
      db.remove(function: .willDelete)
      db.remove(function: .didUpdate)
      db.remove(function: .didInsert)
    }
    let metadatabaseURL = try URL.metadatabase(container: container)
    try database.write { db in
      try SQLQueryExpression(
        "DETACH DATABASE \(quote: .sharingGRDBCloudKitSchemaName)"
      )
      .execute(db)
    }
    try FileManager.default.removeItem(at: metadatabaseURL)
  }

  func deleteLocalData() throws {
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

  func didInsert(recordName: String, zoneName: String) {
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

  func didUpdate(recordName: String, zoneName: String) {
    // TODO: Check user modification dates
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
    return nil
  }

  private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
    switch event.changeType {
    case .signIn:
      for table in tables.values {
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
              try T
                .where {
                  SQLQueryExpression("\($0.primaryKey) = \(bind: deletion.recordID.recordName)")
                }
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
    var newPendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] = []
    var newPendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] = []
    defer {
      underlyingSyncEngine.state.add(pendingDatabaseChanges: newPendingDatabaseChanges)
      underlyingSyncEngine.state.add(pendingRecordZoneChanges: newPendingRecordZoneChanges)
    }

    for savedRecord in event.savedRecords {
      refreshLastKnownServerRecord(savedRecord)
    }

    for failedRecordSave in event.failedRecordSaves {
    }
  }

  private func mergeFromServerRecord(_ record: CKRecord) {
    withErrorReporting(.sharingGRDBCloudKitFailure) {
      let localModificationDate = try database.read { db in
        try Record.for(record).select(\.localModificationDate).fetchOne(db)
      }
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
        let localModificationDate,
        localModificationDate > record.modificationDate ?? .distantPast
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
        }
        return
      }
    }
  }

  private func refreshLastKnownServerRecord(_ record: CKRecord) {
    let query = Record.for(record)
    let lastKnownServerRecord =
      withErrorReporting(.sharingGRDBCloudKitFailure) {
        try database.read { db in
          try query
            .select(\.lastKnownServerRecord)
            .fetchOne(db)
        }
          ?? nil
      }
      ?? nil

    let localRecord =
      lastKnownServerRecord
      ?? CKRecord(
        recordType: record.recordID.zoneID.zoneName,
        recordID: record.recordID
      )

    func updateLastKnownServerRecord() {
      withErrorReporting(.sharingGRDBCloudKitFailure) {
        try database.write { db in
          try query
            .update { $0.lastKnownServerRecord = record }
            .execute(db)
        }
      }
    }

    if let lastKnownDate = localRecord.modificationDate {
      if let recordDate = record.modificationDate, lastKnownDate < recordDate {
        updateLastKnownServerRecord()
      }
    } else {
      updateLastKnownServerRecord()
    }
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
  fileprivate static var didInsert: Self {
    Self("didInsert") {
      @Dependency(\.defaultSyncEngine) var defaultSyncEngine
      await defaultSyncEngine.didInsert(recordName: $0, zoneName: $1)
    }
  }

  fileprivate static var didUpdate: Self {
    Self("didUpdate") {
      @Dependency(\.defaultSyncEngine) var defaultSyncEngine
      await defaultSyncEngine.didUpdate(recordName: $0, zoneName: $1)
    }
  }

  fileprivate static var willDelete: Self {
    Self("willDelete") {
      @Dependency(\.defaultSyncEngine) var defaultSyncEngine
      await defaultSyncEngine.willDelete(recordName: $0, zoneName: $1)
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
        \(quote: Base.tableName, delimiter: .text),
        \(quote: operation == .delete ? "old" : "new").\(quote: Base.columns.primaryKey.name)
      );
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
    if let queryBindable = self as? any QueryBindable {
      return queryBindable.queryFragment
    } else {
      return "\(.invalid(Unbindable()))"
    }
  }
}

private struct Unbindable: Error {}

extension String {
  fileprivate static let sharingGRDBCloudKitSchemaName = "sharing_grdb_icloud"
  fileprivate static let sharingGRDBCloudKitFailure = "SharingGRDB CloudKit Failure"
}

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
extension URL {
  fileprivate static func metadatabase(container: CKContainer) throws -> Self {
    try FileManager.default.createDirectory(
      at: applicationSupportDirectory,
      withIntermediateDirectories: true
    )
    return applicationSupportDirectory.appending(
      component: "\(container.containerIdentifier.map { "\($0)." } ?? "")sharing-grdb-icloud.sqlite"
    )
  }
}

@available(iOS 14, macOS 11, tvOS 14, watchOS 7, *)
private let logger = Logger(subsystem: "SharingGRDB", category: "CloudKit")
