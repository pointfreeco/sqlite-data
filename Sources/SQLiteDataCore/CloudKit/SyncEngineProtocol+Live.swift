#if canImport(CloudKit)
import CloudKit

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngine: SyncEngineProtocol {
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
