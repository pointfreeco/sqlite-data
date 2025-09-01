import CloudKit
import ConcurrencyExtras
import CustomDump
import OrderedCollections
import SharingGRDBCore
import Testing

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension PrimaryKeyedTable where PrimaryKey.QueryOutput: IdentifierStringConvertible {
  static func recordID(
    for id: PrimaryKey.QueryOutput,
    zoneID: CKRecordZone.ID? = nil
  ) -> CKRecord.ID {
    CKRecord.ID(
      recordName: self.recordName(for: id),
      zoneID: zoneID ?? SyncEngine.defaultTestZone.zoneID
    )
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngine {
  struct ModifyRecordsCallback {
    fileprivate let operation: @Sendable () async -> Void
    func notify() async {
      await operation()
    }
  }

  func modifyRecordZones(
    scope: CKDatabase.Scope,
    saving recordZonesToSave: [CKRecordZone] = [],
    deleting recordZoneIDsToDelete: [CKRecordZone.ID] = []
  ) throws -> ModifyRecordsCallback {
    let syncEngine = syncEngine(for: scope)

    let (saveResults, deleteResults) = try syncEngine.database.modifyRecordZones(
      saving: recordZonesToSave,
      deleting: recordZoneIDsToDelete
    )

    return ModifyRecordsCallback {
      await syncEngine.delegate
        .handleEvent(
          .fetchedDatabaseChanges(
            modifications: saveResults.values.compactMap { try? $0.get().zoneID },
            deletions: deleteResults.compactMap { zoneID, result in
              ((try? result.get()) != nil)
                ? (zoneID, .deleted)
                : nil
            }
          ),
          syncEngine: syncEngine
        )
    }
  }

  func modifyRecords(
    scope: CKDatabase.Scope,
    saving recordsToSave: [CKRecord] = [],
    deleting recordIDsToDelete: [CKRecord.ID] = []
  ) throws -> ModifyRecordsCallback {
    let syncEngine = syncEngine(for: scope)
    let recordsToDeleteByID = Dictionary(
      grouping: syncEngine.database.storage.withValue { storage in
        recordIDsToDelete.compactMap { recordID in storage[recordID.zoneID]?[recordID] }
      },
      by: \.recordID
    )
    .compactMapValues(\.first)

    let (saveResults, deleteResults) = try syncEngine.database.modifyRecords(
      saving: recordsToSave,
      deleting: recordIDsToDelete
    )

    return ModifyRecordsCallback {
      await syncEngine.delegate.handleEvent(
        .fetchedRecordZoneChanges(
          modifications: saveResults.values.compactMap { try? $0.get() },
          deletions: deleteResults.compactMap { recordID, result in
            syncEngine.database.storage.withValue { storage in
              (recordsToDeleteByID[recordID]?.recordType).flatMap { recordType in
                (try? result.get()) != nil
                  ? (recordID, recordType)
                  : nil
              }
            }
          }
        ),
        syncEngine: syncEngine
      )
    }
  }

  func processPendingRecordZoneChanges(
    options: CKSyncEngine.SendChangesOptions = CKSyncEngine.SendChangesOptions(),
    scope: CKDatabase.Scope,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws {
    let syncEngine = syncEngine(for: scope)
    guard !syncEngine.state.pendingRecordZoneChanges.isEmpty
    else {
      Issue.record(
        "Processing empty set of record zone changes.",
        sourceLocation: SourceLocation.init(
          fileID: String(describing: fileID),
          filePath: String(describing: filePath),
          line: Int(line),
          column: Int(column)
        )
      )
      return
    }
    guard try await container.accountStatus() == .available
    else {
      Issue.record(
        """
        User must be logged in to process pending changes.
        """,
        sourceLocation: SourceLocation.init(
          fileID: String(describing: fileID),
          filePath: String(describing: filePath),
          line: Int(line),
          column: Int(column)
        )
      )
      return
    }
    
    let batch = await nextRecordZoneChangeBatch(
      reason: .scheduled,
      options: options,
      syncEngine: {
        switch scope {
        case .private:
          self.private
        case .shared:
          self.shared
        case .public:
          fatalError("Public database not supported in tests.")
        @unknown default:
          fatalError("Unknown database scope not supported in tests.")
        }
      }()
    )
    guard let batch
    else { return }

    let (saveResults, deleteResults) = try syncEngine.database.modifyRecords(
      saving: batch.recordsToSave,
      deleting: batch.recordIDsToDelete,
      savePolicy: .ifServerRecordUnchanged,
      atomically: true
    )

    var savedRecords: [CKRecord] = []
    var failedRecordSaves: [(record: CKRecord, error: CKError)] = []
    var deletedRecordIDs: [CKRecord.ID] = []
    var failedRecordDeletes: [CKRecord.ID: CKError] = [:]
    for (recordID, result) in saveResults {
      switch result {
      case .success(let record):
        savedRecords.append(record)
      case .failure(let error as CKError):
        guard let record = batch.recordsToSave.first(where: { $0.recordID == recordID })
        else { fatalError("\(recordID.debugDescription) not found in pending changes") }
        failedRecordSaves.append((record: record, error: error))
      case .failure:
        fatalError("Mocks should only raise 'CKError' values.")
      }
    }
    for (recordID, result) in deleteResults {
      switch result {
      case .success:
        deletedRecordIDs.append(recordID)
      case .failure(let error as CKError):
        failedRecordDeletes[recordID] = error
      case .failure:
        fatalError("Mocks should only raise 'CKError' values.")
      }
    }
    syncEngine.state.remove(
      pendingRecordZoneChanges: savedRecords.map { .saveRecord($0.recordID) }
    )
    syncEngine.state.remove(
      pendingRecordZoneChanges: deletedRecordIDs.map { .deleteRecord($0) }
    )

    await syncEngine.delegate
      .handleEvent(
        .sentRecordZoneChanges(
          savedRecords: savedRecords,
          failedRecordSaves: failedRecordSaves,
          deletedRecordIDs: deletedRecordIDs,
          failedRecordDeletes: failedRecordDeletes
        ),
        syncEngine: syncEngine
      )
  }

  func processPendingDatabaseChanges(
    scope: CKDatabase.Scope,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws {
    let syncEngine = syncEngine(for: scope)
    guard !syncEngine.state.pendingDatabaseChanges.isEmpty
    else {
      Issue.record(
        "Processing empty set of database changes.",
        sourceLocation: SourceLocation.init(
          fileID: String(describing: fileID),
          filePath: String(describing: filePath),
          line: Int(line),
          column: Int(column)
        )
      )
      return
    }
    guard try await container.accountStatus() == .available
    else {
      Issue.record(
        """
        User must be logged in to process pending changes.
        """,
        sourceLocation: SourceLocation.init(
          fileID: String(describing: fileID),
          filePath: String(describing: filePath),
          line: Int(line),
          column: Int(column)
        )
      )
      return
    }

    var zonesToSave: [CKRecordZone] = []
    var zoneIDsToDelete: [CKRecordZone.ID] = []
    for pendingDatabaseChange in syncEngine.state.pendingDatabaseChanges {
      switch pendingDatabaseChange {
      case .saveZone(let zone):
        zonesToSave.append(zone)
      case .deleteZone(let zoneID):
        zoneIDsToDelete.append(zoneID)
      @unknown default:
        fatalError("Unsupported pendingDatabaseChange: \(pendingDatabaseChange)")
      }
    }
    let results:
      (
        saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
        deleteResults: [CKRecordZone.ID: Result<Void, any Error>]
      ) = try syncEngine.database.modifyRecordZones(
        saving: zonesToSave,
        deleting: zoneIDsToDelete
      )
    var savedZones: [CKRecordZone] = []
    var failedZoneSaves: [(zone: CKRecordZone, error: CKError)] = []
    var deletedZoneIDs: [CKRecordZone.ID] = []
    var failedZoneDeletes: [CKRecordZone.ID: CKError] = [:]
    for (zoneID, saveResult) in results.saveResults {
      switch saveResult {
      case .success(let zone):
        savedZones.append(zone)
      case .failure(let error as CKError):
        failedZoneSaves.append((zonesToSave.first(where: { $0.zoneID == zoneID })!, error))
      case .failure(let error):
        reportIssue("Error thrown not CKError: \(error)")
      }
    }
    for (zoneID, deleteResult) in results.deleteResults {
      switch deleteResult {
      case .success:
        deletedZoneIDs.append(zoneID)
      case .failure(let error as CKError):
        failedZoneDeletes[zoneID] = error
      case .failure(let error):
        reportIssue("Error thrown not CKError: \(error)")
      }
    }

    syncEngine.state.remove(pendingDatabaseChanges: savedZones.map { .saveZone($0) })
    syncEngine.state.remove(pendingDatabaseChanges: deletedZoneIDs.map { .deleteZone($0) })

    await syncEngine.delegate
      .handleEvent(
        .sentDatabaseChanges(
          savedZones: savedZones,
          failedZoneSaves: failedZoneSaves,
          deletedZoneIDs: deletedZoneIDs,
          failedZoneDeletes: failedZoneDeletes
        ),
        syncEngine: syncEngine
      )
  }

  private func syncEngine(for scope: CKDatabase.Scope) -> MockSyncEngine {
    switch scope {
    case .public:
      fatalError("Public database not supported in tests.")
    case .private:
      `private`
    case .shared:
      shared
    @unknown default:
      fatalError("Unknown database scope not supported in tests.")
    }
  }
}
