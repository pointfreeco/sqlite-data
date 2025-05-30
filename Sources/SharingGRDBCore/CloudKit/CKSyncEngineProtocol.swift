import CloudKit

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package protocol CKSyncEngineProtocol<State>: AnyObject, Sendable {
  associatedtype State: CKSyncEngineStateProtocol
  func fetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws
  var state: State { get }
  var scope: CKDatabase.Scope { get }
}
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngineProtocol {
  package func fetchChanges() async throws {
    try await fetchChanges(CKSyncEngine.FetchChangesOptions())
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package protocol CKSyncEngineStateProtocol: Sendable {
  func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
  func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
  func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
  func remove(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngine: CKSyncEngineProtocol {
  package var scope: CKDatabase.Scope {
    database.databaseScope
  }
}
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngine.State: CKSyncEngineStateProtocol {
}
