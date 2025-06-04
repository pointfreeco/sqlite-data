import CloudKit

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngine: SyncEngineProtocol {
  package var scope: CKDatabase.Scope {
    database.databaseScope
  }

  package func acceptShare(metadata: ShareMetadata) async throws {
    guard let metadata = metadata.rawValue
    else {
      reportIssue("TODO")
      return
    }
    guard let rootRecordID = metadata.hierarchicalRootRecordID
    else {
      reportIssue("TODO")
      return
    }
    let container = CKContainer(identifier: metadata.containerIdentifier)
    try await container.accept(metadata)
    try await fetchChanges(
      .init(
        scope: .zoneIDs([rootRecordID.zoneID]),
        operationGroup: nil
      )
    )
  }
}
@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngine.State: CKSyncEngineStateProtocol {
}
