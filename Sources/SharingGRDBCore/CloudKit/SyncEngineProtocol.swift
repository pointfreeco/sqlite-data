#if canImport(CloudKit)
import CloudKit

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package protocol SyncEngineProtocol<State>: AnyObject, Sendable {
  associatedtype State: CKSyncEngineStateProtocol
  func fetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws
  var state: State { get }
  var scope: CKDatabase.Scope { get }
  func acceptShare(metadata: ShareMetadata) async throws
  func cancelOperations() async
  func recordZoneChangeBatch(
    pendingChanges: [CKSyncEngine.PendingRecordZoneChange],
    recordProvider: @Sendable (CKRecord.ID) async -> CKRecord?
  ) async -> CKSyncEngine.RecordZoneChangeBatch?
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngineProtocol {
  package func fetchChanges() async throws {
    try await fetchChanges(CKSyncEngine.FetchChangesOptions())
  }
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

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package struct SendChangesContext: Sendable {
  package var reason: CKSyncEngine.SyncReason
  package var options: CKSyncEngine.SendChangesOptions
  package init(
    reason: CKSyncEngine.SyncReason = .scheduled,
    options: CKSyncEngine.SendChangesOptions = CKSyncEngine.SendChangesOptions(scope: .all)
  ) {
    self.reason = reason
    self.options = options
  }
  init(context: CKSyncEngine.SendChangesContext) {
    reason = context.reason
    options = context.options
  }
#endif
