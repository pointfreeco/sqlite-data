#if canImport(CloudKit)
import CloudKit

// TODO: make AnyObject
package protocol CloudContainerProtocol: Equatable, Hashable, Sendable {
  var sharedDatabase: any CloudDatabase { get }
  var privateDatabase: any CloudDatabase { get }
  func database(for recordID: CKRecord.ID) -> any CloudDatabase
  @available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
  func shareMetadata(for url: URL, shouldFetchRootRecord: Bool) async throws -> CKShare.Metadata
}

extension CloudContainerProtocol {
  package func database(for recordID: CKRecord.ID) -> any CloudDatabase {
    if recordID.zoneID.ownerName != CKCurrentUserDefaultName {
      print("?!?!?!")
    }
    return recordID.zoneID.ownerName == CKCurrentUserDefaultName
    ? privateDatabase
    : sharedDatabase
  }
}

extension CKContainer: CloudContainerProtocol {
  package var sharedDatabase: any CloudDatabase {
    sharedCloudDatabase
  }

  package var privateDatabase: any CloudDatabase {
    privateCloudDatabase
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
