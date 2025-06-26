#if canImport(CloudKit)
import CloudKit

package protocol CloudContainerProtocol: AnyObject, Equatable, Hashable, Sendable {
  var rawValue: CKContainer { get }
  var privateDatabase: any CloudDatabase { get }
  var sharedDatabase: any CloudDatabase { get }
  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  func shareMetadata(for url: URL, shouldFetchRootRecord: Bool) async throws -> CKShare.Metadata
}

extension CloudContainerProtocol {
  package func database(for recordID: CKRecord.ID) -> any CloudDatabase {
    recordID.zoneID.ownerName == CKCurrentUserDefaultName
    ? privateDatabase
    : sharedDatabase
  }
}

extension CKContainer: CloudContainerProtocol {
  package var rawValue: CKContainer {
    self
  }

  package var privateDatabase: any CloudDatabase {
    privateCloudDatabase
  }
  
  package var sharedDatabase: any CloudDatabase {
    sharedCloudDatabase
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
