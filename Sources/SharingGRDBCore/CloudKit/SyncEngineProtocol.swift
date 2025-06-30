#if canImport(CloudKit)
import CloudKit

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package protocol SyncEngineDelegate: AnyObject, Sendable {
  func handleEvent(_ event: SyncEngine.Event, syncEngine: any SyncEngineProtocol) async
  func nextRecordZoneChangeBatch(
    reason: CKSyncEngine.SyncReason,
    options: CKSyncEngine.SendChangesOptions,
    syncEngine: any SyncEngineProtocol
  ) async -> CKSyncEngine.RecordZoneChangeBatch?
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package protocol SyncEngineProtocol<Database, State>: AnyObject, Sendable {
  associatedtype State: CKSyncEngineStateProtocol
  associatedtype Database: CloudDatabase

  var database: Database { get }
  var state: State { get }

  func cancelOperations() async
  func fetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws
  func recordZoneChangeBatch(
    pendingChanges: [CKSyncEngine.PendingRecordZoneChange],
    recordProvider: @Sendable (CKRecord.ID) async -> CKRecord?
  ) async -> CKSyncEngine.RecordZoneChangeBatch?
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package struct ShareMetadata: Hashable {
  package var containerIdentifier: String
  package var hierarchicalRootRecordID: CKRecord.ID?
  package var rawValue: CKShare.Metadata?
  package init(rawValue: CKShare.Metadata) {
    self.containerIdentifier = rawValue.containerIdentifier
    self.hierarchicalRootRecordID = rawValue.hierarchicalRootRecordID
    self.rawValue = rawValue
  }
  package init(containerIdentifier: String, hierarchicalRootRecordID: CKRecord.ID?) {
    self.containerIdentifier = containerIdentifier
    self.hierarchicalRootRecordID = hierarchicalRootRecordID
    self.rawValue = nil
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package protocol CKSyncEngineStateProtocol: Sendable {
  var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] { get }
  func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
  func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
  func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
  func remove(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
}
#endif
