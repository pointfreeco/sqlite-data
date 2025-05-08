import CloudKit
import Dependencies
import SharingGRDB

extension DependencyValues {
  var cloudKitDatabase: CloudKitDatabase {
    get {
      self[CloudKitDatabase.self]
    }
    set {
      self[CloudKitDatabase.self] = newValue
    }
  }
}
extension CloudKitDatabase: TestDependencyKey {
  static var testValue: CloudKitDatabase {
    if shouldReportUnimplemented {
      reportIssue("TODO")
    }
    return CloudKitDatabase(container: CKContainer(identifier: "default"))
  }
}

// TODO: fix sendable by either making actor or locking mutable state
class CloudKitDatabase: @unchecked Sendable {
  let container: CKContainer
  let syncEngine: CKSyncEngine
  var stateSerialization: CKSyncEngine.State.Serialization?
  let delegate = Delegate()

  init(container: CKContainer) {
    self.container = container

    var configuration = CKSyncEngine.Configuration(
      database: container.privateCloudDatabase,
      stateSerialization: stateSerialization,
      delegate: delegate
    )
    configuration.automaticallySync = true
    syncEngine = CKSyncEngine(configuration)
  }

  func saveZones(tableNames: [String]) {
    syncEngine.state.add(
      pendingDatabaseChanges: tableNames.map { .saveZone(CKRecordZone(zoneName: $0)) }
    )
  }

  func didInsert(tableName: String, id: String) {
    syncEngine.state.add(
      pendingRecordZoneChanges: [
        .saveRecord(
          CKRecord.ID(
            recordName: id,
            zoneID: CKRecordZone(zoneName: tableName).zoneID
          )
        )
      ]
    )
  }

  func didUpdate(tableName: String, id: String) {
    // TODO: perform modification date checks
    syncEngine.state.add(
      pendingRecordZoneChanges: [
        .saveRecord(
          CKRecord.ID(
            recordName: id,
            zoneID: CKRecordZone(zoneName: tableName).zoneID
          )
        )
      ]
    )
  }

  func willDelete(tableName: String, id: String) {
    syncEngine.state.add(
      pendingRecordZoneChanges: [
        .deleteRecord(
          CKRecord.ID(
            recordName: id,
            zoneID: CKRecordZone(zoneName: tableName).zoneID
          )
        )
      ]
    )

//    let contacts = ids.compactMap { self.appData.contacts[$0] }
//    for id in ids {
//      self.appData.contacts[id] = nil
//    }
//    try self.persistLocalData()
//
//    let pendingDeletions: [CKSyncEngine.PendingRecordZoneChange] = contacts.map { .deleteRecord($0.recordID) }
//    self.syncEngine.state.add(pendingRecordZoneChanges: pendingDeletions)

  }
}

final class Delegate: CKSyncEngineDelegate {

  func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
    logger.info("CloudKitDatabase.Delegate.handleEvent.\(event)")
    switch event {
    case .stateUpdate(_):
      // TODO
      break
    case .accountChange(_):
      // TODO
      break
    case .fetchedDatabaseChanges(_):
      // TODO
      break
    case .fetchedRecordZoneChanges(_):
      // TODO
      break
    case .sentDatabaseChanges(_):
      // TODO
      break
    case .sentRecordZoneChanges(_):
      // TODO
      break
    case .willFetchChanges(_):
      // TODO
      break
    case .willFetchRecordZoneChanges(_):
      // TODO
      break
    case .didFetchRecordZoneChanges(_):
      // TODO
      break
    case .didFetchChanges(_):
      // TODO
      break
    case .willSendChanges(_):
      // TODO
      break
    case .didSendChanges(_):
      // TODO
      break
    @unknown default:
      // TODO
      break
    }
  }

  func nextRecordZoneChangeBatch(
    _ context: CKSyncEngine.SendChangesContext,
    syncEngine: CKSyncEngine
  ) async -> CKSyncEngine.RecordZoneChangeBatch? {
    logger.info("CloudKitDatabase.Delegate.nextRecordZoneChangeBatch \(context)")

    let changes = syncEngine.state.pendingRecordZoneChanges.filter(context.options.scope.contains)
    let batch = await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
      let primaryKey = recordID.recordName
      let tableName = recordID.zoneID.zoneName

      // TODO: fetch record data from centralized table
      let record = CKRecord(recordType: tableName, recordID: recordID)

      @Dependency(\.defaultDatabase) var database
      let row = withErrorReporting {
        try database.read { db in
          try Row.fetchOne(
            db,
            SQLRequest(
              sql: """
                SELECT * FROM "\(tableName)" WHERE "id" = ?
                """,
              arguments: [primaryKey]
            )
          )
        }
      }

      guard
        let row, // No error was thrown from fetchOne
        let row  // fetchOne returned a value
      else {
        syncEngine.state.remove(pendingRecordZoneChanges: [ .saveRecord(recordID) ])
        return nil
      }

      for columnName in row.columnNames {
        switch row[columnName]?.databaseValue.storage {
        case .null:
          record.encryptedValues[columnName] = nil
        case .int64(let value):
          record.encryptedValues[columnName] = value
        case .double(let value):
          record.encryptedValues[columnName] = value
        case .string(let value):
          record.encryptedValues[columnName] = value
        case .blob(let value):
          record.encryptedValues[columnName] = value
        case .none:
          break
        }
      }
      // TODO: save new record in centralized table

      return record
    }
    return batch
  }

  //  func nextFetchChangesOptions(
  //    _ context: CKSyncEngine.FetchChangesContext,
  //    syncEngine: CKSyncEngine
  //  ) async -> CKSyncEngine.FetchChangesOptions {
  //
  //  }
}
