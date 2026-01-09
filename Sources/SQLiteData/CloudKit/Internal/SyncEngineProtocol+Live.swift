#if canImport(CloudKit)
  import CloudKit

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngine: SyncEngineProtocol {
  package var pendingRecordZoneChanges: [PendingRecordZoneChange] {
    state.pendingRecordZoneChanges
  }

  package var pendingDatabaseChanges: [PendingDatabaseChange] {
    state.pendingDatabaseChanges
  }

  package func add(pendingRecordZoneChanges: [PendingRecordZoneChange]) {
    state.add(pendingRecordZoneChanges: pendingRecordZoneChanges)
  }

  package func remove(pendingRecordZoneChanges: [PendingRecordZoneChange]) {
    state.remove(pendingRecordZoneChanges: pendingRecordZoneChanges)
  }

  package func add(pendingDatabaseChanges: [PendingDatabaseChange]) {
    state.add(pendingDatabaseChanges: pendingDatabaseChanges)
  }

  package func remove(pendingDatabaseChanges: [PendingDatabaseChange]) {
    state.remove(pendingDatabaseChanges: pendingDatabaseChanges)
  }

    package func recordZoneChangeBatch(
      pendingChanges: [PendingRecordZoneChange],
      recordProvider: @Sendable (CKRecord.ID) async -> CKRecord?
    ) async -> RecordZoneChangeBatch? {
      await CKSyncEngine
        .RecordZoneChangeBatch(pendingChanges: pendingChanges, recordProvider: recordProvider)
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  extension CKSyncEngine.State: CKSyncEngineStateProtocol {
  }
#endif
