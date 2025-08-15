#if canImport(CloudKit)
import CloudKit

@available(macOS 12, *)
package protocol CloudContainer<Database>: AnyObject, Equatable, Hashable, Sendable {
  associatedtype Database: CloudDatabase

  func accountStatus() async throws -> CKAccountStatus
  var containerIdentifier: String? { get }
  var rawValue: CKContainer { get }
  var privateCloudDatabase: Database { get }
  func accept(_ metadata: ShareMetadata) async throws -> CKShare
  static func createContainer(identifier containerIdentifier: String) -> Self
  var sharedCloudDatabase: Database { get }
  @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
  func shareMetadata(for share: CKShare, shouldFetchRootRecord: Bool) async throws -> ShareMetadata
}

@available(macOS 12, *)
package struct ShareMetadata: Hashable {
  package var containerIdentifier: String
  package var hierarchicalRootRecordID: CKRecord.ID?
  package var rootRecord: CKRecord?
  package var rawValue: CKShare.Metadata?
  package init(rawValue: CKShare.Metadata) {
    self.containerIdentifier = rawValue.containerIdentifier
    self.hierarchicalRootRecordID = rawValue.hierarchicalRootRecordID
    self.rootRecord = rawValue.rootRecord
    self.rawValue = rawValue
  }
  package init(
    containerIdentifier: String,
    hierarchicalRootRecordID: CKRecord.ID?,
    rootRecord: CKRecord?
  ) {
    self.containerIdentifier = containerIdentifier
    self.hierarchicalRootRecordID = hierarchicalRootRecordID
    self.rootRecord = rootRecord
    self.rawValue = nil
  }
}

@available(macOS 12, *)
extension CloudContainer {
  package func database(for recordID: CKRecord.ID) -> any CloudDatabase {
    recordID.zoneID.ownerName == CKCurrentUserDefaultName
    ? privateCloudDatabase
    : sharedCloudDatabase
  }
}

@available(macOS 12, *)
extension CKContainer: CloudContainer {
  package func accept(_ metadata: ShareMetadata) async throws -> CKShare {
    guard let metadata = metadata.rawValue
    else {
      fatalError("This should never be called with 'ShareMetadata' that has a nil 'rawValue'")
    }
    return try await self.accept(metadata)
  }

  package static func createContainer(identifier containerIdentifier: String) -> Self {
    Self(identifier: containerIdentifier)
  }

  package var rawValue: CKContainer {
    self
  }

  @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
  package func shareMetadata(
    for share: CKShare,
    shouldFetchRootRecord: Bool = false
  ) async throws -> ShareMetadata {
    try await withUnsafeThrowingContinuation { continuation in
      let operation = CKFetchShareMetadataOperation(shareURLs: [share.url].compactMap(\.self))
      operation.shouldFetchRootRecord = true
      operation.perShareMetadataResultBlock = { url, result in
        continuation.resume(with: result.map(ShareMetadata.init(rawValue:)))
      }
      add(operation)
    }
  }
}
#endif
