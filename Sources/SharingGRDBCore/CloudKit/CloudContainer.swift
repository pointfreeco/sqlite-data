#if canImport(CloudKit)
import CloudKit

package protocol CloudContainer<Database>: AnyObject, Equatable, Hashable, Sendable {
  associatedtype Database: CloudDatabase

  var rawValue: CKContainer { get }
  var privateCloudDatabase: Database { get }
  var sharedCloudDatabase: Database { get }
  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  func shareMetadata(for url: URL, shouldFetchRootRecord: Bool) async throws -> CKShare.Metadata
}

extension CloudContainer {
  package func database(for recordID: CKRecord.ID) -> any CloudDatabase {
    recordID.zoneID.ownerName == CKCurrentUserDefaultName
    ? privateCloudDatabase
    : sharedCloudDatabase
  }
}

extension CKContainer: CloudContainer {
  package var rawValue: CKContainer {
    self
  }

  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  package func shareMetadata(
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
}
#endif
