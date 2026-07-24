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
    }
  }

  func modifyRecords(
    scope: CKDatabase.Scope,
    saving recordsToSave: [CKRecord] = [],
    deleting recordIDsToDelete: [CKRecord.ID] = [],
    atomically: Bool = true
  ) throws -> ModifyRecordsCallback {
    let syncEngine = syncEngine(for: scope)
    let recordsToDeleteByID = Dictionary(
      grouping: syncEngine.database.state.withValue { state in
        recordIDsToDelete.compactMap {
          recordID in state.storage[recordID.zoneID]?.records[recordID]
        }
      },
      by: \.recordID
    )
    .compactMapValues(\.first)

    let (saveResults, deleteResults) = try syncEngine.database.modifyRecords(
      saving: recordsToSave,
      deleting: recordIDsToDelete,
      atomically: atomically
    )

    return ModifyRecordsCallback {
      await syncEngine.parentSyncEngine.handleEvent(
        .fetchedRecordZoneChanges(
          modifications: saveResults.compactMap { recordID, result in
            guard case .success = result else { return nil }
            // NB: Read the latest version from the database in case the record has been
            //     modified between the original save and when this callback is invoked.
            return try? syncEngine.database.record(for: recordID)
          },
          deletions: deleteResults.compactMap { recordID, result in
            guard case .success = result else { return nil }
            // NB: Skip if the record has been re-saved between the original delete and
            //     when this callback is invoked.
            guard (try? syncEngine.database.record(for: recordID)) == nil else { return nil }
            guard let record = recordsToDeleteByID[recordID] else { return nil }
            return (recordID, record.recordType)
          }
        ),
        syncEngine: syncEngine
      )
    }
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
