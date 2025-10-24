import CloudKit
import ConcurrencyExtras
import CustomDump
import OrderedCollections
import SQLiteData
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
  struct ModifyRecordsCallback<ReturnValue> {
    fileprivate let operation: @Sendable () async -> ReturnValue
    @discardableResult
    func notify() async -> ReturnValue {
      await operation()
    }
  }

  func modifyRecordZones(
    scope: CKDatabase.Scope,
    saving recordZonesToSave: [CKRecordZone] = [],
    deleting recordZoneIDsToDelete: [CKRecordZone.ID] = []
  ) throws -> ModifyRecordsCallback<
    (
      saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
      deleteResults: [CKRecordZone.ID: Result<Void, any Error>]
    )
  > {
    let syncEngine = syncEngine(for: scope)

    let (saveResults, deleteResults) = try syncEngine.database.modifyRecordZones(
      saving: recordZonesToSave,
      deleting: recordZoneIDsToDelete
    )

    return ModifyRecordsCallback {
      await syncEngine.parentSyncEngine
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
      return (saveResults, deleteResults)
    }
  }

  func modifyRecords(
    scope: CKDatabase.Scope,
    saving recordsToSave: [CKRecord] = [],
    deleting recordIDsToDelete: [CKRecord.ID] = []
  ) throws -> ModifyRecordsCallback<
    (
      saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
      deleteResults: [CKRecord.ID: Result<Void, any Error>]
    )
  > {
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
      await syncEngine.parentSyncEngine.handleEvent(
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
      return (saveResults, deleteResults)
    }
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
        sourceLocation: SourceLocation(
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
        sourceLocation: SourceLocation(
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

    await syncEngine.parentSyncEngine
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
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension MockSyncEngine {
  package func assertFetchChangesScopes(
    _ scopes: [CKSyncEngine.FetchChangesOptions.Scope],
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    _fetchChangesScopes.withValue {
      expectNoDifference(
        scopes,
        $0,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      $0.removeAll()
    }
  }

  package func assertAcceptedShareMetadata(
    _ sharedMetadata: Set<ShareMetadata>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    _acceptedShareMetadata.withValue {
      expectNoDifference(
        sharedMetadata,
        $0,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      $0.removeAll()
    }
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension MockSyncEngineState {
  package func assertPendingRecordZoneChanges(
    _ changes: OrderedSet<CKSyncEngine.PendingRecordZoneChange>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    _pendingRecordZoneChanges.withValue {
      expectNoDifference(
        Set(changes),
        Set($0),
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      $0.removeAll()
    }
  }

  package func assertPendingDatabaseChanges(
    _ changes: OrderedSet<CKSyncEngine.PendingDatabaseChange>,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) {
    _pendingDatabaseChanges.withValue {
      expectNoDifference(
        Set(changes),
        Set($0),
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
      $0.removeAll()
    }
  }

}
