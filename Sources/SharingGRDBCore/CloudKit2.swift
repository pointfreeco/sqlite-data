import CloudKit
import OSLog

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
public final actor SyncEngine {
  nonisolated let container: CKContainer
  nonisolated let database: any DatabaseWriter
  nonisolated let tables: [any StructuredQueriesCore.PrimaryKeyedTable.Type]
  lazy var stateSerialization: CKSyncEngine.State.Serialization? =
    withErrorReporting {
      if let data = try? Data(contentsOf: .stateSerialization(container: container)) {
        return try JSONDecoder().decode(CKSyncEngine.State.Serialization?.self, from: data)
      } else {
        return nil
      }
    } ?? nil
  {
    didSet {
      withErrorReporting {
        if let stateSerialization {
          try JSONEncoder()
            .encode(stateSerialization)
            .write(to: .stateSerialization(container: container))
        } else {
          try FileManager.default.removeItem(at: .stateSerialization(container: container))
        }
      }
    }
  }
  lazy var underlyingSyncEngine: CKSyncEngine = defaultSyncEngine

  public init(
    container: CKContainer,
    database: any DatabaseWriter,
    tables: [any StructuredQueriesCore.PrimaryKeyedTable.Type]
  ) {
    self.container = container
    self.database = database
    self.tables = tables
    Task { _ = await underlyingSyncEngine }
  }

  func deleteLocalData() {
    withErrorReporting {
      try database.write { db in
        for table in tables {
          db.deleteAll(tableName: table.tableName)
        }
      }
    }
    stateSerialization = nil
    underlyingSyncEngine = defaultSyncEngine
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
      for table in tables {
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
      deleteLocalData()
    @unknown default:
      break
    }
  }

  private func handleFetchedDatabaseChanges(_ event: CKSyncEngine.Event.FetchedDatabaseChanges) {
    withErrorReporting {
      try database.write { db in
        for deletion in event.deletions {
          db.deleteAll(tableName: deletion.zoneID.zoneName)
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

extension Database {
  fileprivate func deleteAll(tableName: String) {
    withErrorReporting {
      try SQLQueryExpression("DELETE FROM \(quote: tableName)").execute(self)
    }
  }
}

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
extension URL {
  fileprivate static func stateSerialization(container: CKContainer) throws -> Self {
    try FileManager.default
      .createDirectory(at: applicationSupportDirectory, withIntermediateDirectories: true)
    return applicationSupportDirectory.appending(
      component: "sharing-grdb-icloud\(container.containerIdentifier.map { ".\($0)" } ?? "").json"
    )
  }
}

@available(iOS 14, macOS 11, tvOS 14, watchOS 7, *)
private let logger = Logger(subsystem: "SharingGRDB", category: "CloudKit")
