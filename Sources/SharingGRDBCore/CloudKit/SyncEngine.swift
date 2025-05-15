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
      await withErrorReporting("SharingGRDB CloudKit Failure") {
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
        CREATE TABLE "records" (
          "zoneName" TEXT NOT NULL,
          "recordName" TEXT NOT NULL,
          "recordData" BLOB,
          "userModificationDate" TEXT,
          PRIMARY KEY("zoneName", "recordName")
        ) STRICT
        """
      )
      .execute(db)
      try SQLQueryExpression(
        """
        CREATE TABLE "zones" (
          "zoneName" TEXT PRIMARY KEY NOT NULL,
          "schema" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
      try SQLQueryExpression(
        """
        CREATE TABLE "stateSerialization" (
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
        let existingZone =
          previousZones.first(where: { previousZone in
            currentZone.zoneName == previousZone.zoneName
          })
      else { return true }
      return existingZone.schema != currentZone.schema
    }

    if !zonesToFetch.isEmpty {
      Task {
        await withErrorReporting {
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
        "ATTACH DATABASE \(metadatabaseURL) AS \(quote: .sharingGRDBCloudKitDatabaseName)"
      )
      .execute(db)
    }
  }

  func tearDownSyncEngine() throws {
    let metadatabaseURL = try URL.metadatabase(container: container)
    try database.write { db in
      try SQLQueryExpression(
        "DETACH DATABASE \(quote: .sharingGRDBCloudKitDatabaseName)"
      )
      .execute(db)
    }
    try FileManager.default.removeItem(at: metadatabaseURL)
  }

  func deleteLocalData() throws {
    withErrorReporting {
      try database.write { db in
        for table in tables.values {
          func open<T: PrimaryKeyedTable>(_: T.Type) {
            withErrorReporting {
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
    switch event {
    case .accountChange(let event):
      handleAccountChange(event)
    case .stateUpdate(let event):
      stateSerialization = event.stateSerialization
      withErrorReporting {
        try database.write { db in
          try StateSerialization.insert(
            StateSerialization(id: 1, data: event.stateSerialization)
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
    nil
  }

  private func handleAccountChange(_ event: CKSyncEngine.Event.AccountChange) {
    switch event.changeType {
    case .signIn:
      for table in tables.values {
        underlyingSyncEngine.state.add(
          pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneName: table.tableName))]
        )
        withErrorReporting {
          let names: [String] = try database.read { db in
            func open<T: PrimaryKeyedTable>(_ table: T.Type) throws -> [String] {
              try SQLQueryExpression(
                "SELECT \(table.columns.primaryKey) FROM \(table)",
                as: String.self
              )
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
      withErrorReporting {
        try deleteLocalData()
      }
    @unknown default:
      break
    }
  }

  private func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) {
    withErrorReporting {
      try database.write { db in
        for deletion in event.deletions {
          if let table = tables[deletion.zoneID.zoneName] {
            func open<T: PrimaryKeyedTable>(_: T.Type) {
              withErrorReporting {
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
  }

  private func handleSentRecordZoneChanges(_ event: CKSyncEngine.Event.SentRecordZoneChanges) {
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngine: TestDependencyKey {
  public static var testValue: SyncEngine {
    SyncEngine(container: .default(), database: try! DatabaseQueue(), tables: [])
  }
}

extension String {
  fileprivate static let sharingGRDBCloudKitDatabaseName = "sharing_grdb_icloud"
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
