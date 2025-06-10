import CloudKit

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKContainer {
  func shareMetadata(
    for url: URL,
    shouldFetchRootRecord: Bool = false
  ) async throws -> CKShare.Metadata {
    try await withUnsafeThrowingContinuation { continuation in
      let operation = CKFetchShareMetadataOperation(shareURLs: [url])
      operation.shouldFetchRootRecord = true
      operation.perShareMetadataResultBlock = { url, result in
        continuation.resume(with: result)
      }
      add(operation)
    }
  }

  func database(for recordID: CKRecord.ID) -> CKDatabase {
    recordID.zoneID.ownerName == CKCurrentUserDefaultName
    ? privateCloudDatabase
    : sharedCloudDatabase
  }
}
