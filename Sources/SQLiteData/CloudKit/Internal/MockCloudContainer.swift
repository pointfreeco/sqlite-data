import CloudKit
import CustomDump

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
package final class MockCloudContainer: CloudContainer, CustomDumpReflectable {
  package let _accountStatus: LockIsolated<CKAccountStatus>
  package let containerIdentifier: String?
  package let privateCloudDatabase: MockCloudDatabase
  package let sharedCloudDatabase: MockCloudDatabase

  package init(
    accountStatus: CKAccountStatus = .available,
    containerIdentifier: String?,
    privateCloudDatabase: MockCloudDatabase,
    sharedCloudDatabase: MockCloudDatabase
  ) {
    self._accountStatus = LockIsolated(accountStatus)
    self.containerIdentifier = containerIdentifier
    self.privateCloudDatabase = privateCloudDatabase
    self.sharedCloudDatabase = sharedCloudDatabase

    guard let containerIdentifier else { return }
    @Dependency(\.mockCloudContainers) var mockCloudContainers
    mockCloudContainers.withValue { storage in
      storage[containerIdentifier] = self
    }
  }

  package func accountStatus() -> CKAccountStatus {
    _accountStatus.withValue(\.self)
  }

  package var rawValue: CKContainer {
    fatalError("This should never be called in tests.")
  }

  package func accountStatus() async throws -> CKAccountStatus {
    _accountStatus.withValue { $0 }
  }

  package func shareMetadata(
    for share: CKShare,
    shouldFetchRootRecord: Bool
  ) async throws -> ShareMetadata {
    let database =
      share.recordID.zoneID.ownerName == CKCurrentUserDefaultName
      ? privateCloudDatabase
      : sharedCloudDatabase

    let rootRecord: CKRecord? = database.storage.withValue {
      $0[share.recordID.zoneID]?.values.first { record in
        record.share?.recordID == share.recordID
      }
    }

    return ShareMetadata(
      containerIdentifier: containerIdentifier!,
      hierarchicalRootRecordID: rootRecord?.recordID,
      rootRecord: shouldFetchRootRecord ? rootRecord : nil,
      share: share
    )
  }

  package func accept(_ metadata: ShareMetadata) async throws -> CKShare {
    guard let rootRecord = metadata.rootRecord
    else {
      fatalError("Must provide root record in mock shares during tests.")
    }

    let (saveResults, _) = try sharedCloudDatabase.modifyRecords(
      saving: [metadata.share, rootRecord]
    )
    try saveResults.values.forEach { _ = try $0.get() }
    return metadata.share
  }

  package static func createContainer(identifier containerIdentifier: String) -> MockCloudContainer
  {
    @Dependency(\.mockCloudContainers) var mockCloudContainers
    return mockCloudContainers.withValue { storage in
      let container: MockCloudContainer
      if let existingContainer = storage[containerIdentifier] {
        return existingContainer
      } else {
        container = MockCloudContainer(
          accountStatus: .available,
          containerIdentifier: containerIdentifier,
          privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
          sharedCloudDatabase: MockCloudDatabase(databaseScope: .shared)
        )
        container.privateCloudDatabase.set(container: container)
        container.sharedCloudDatabase.set(container: container)
      }
      storage[containerIdentifier] = container
      return container
    }
  }

  package static func == (lhs: MockCloudContainer, rhs: MockCloudContainer) -> Bool {
    lhs === rhs
  }

  package func hash(into hasher: inout Hasher) {
    hasher.combine(ObjectIdentifier(self))
  }

  package var customDumpMirror: Mirror {
    Mirror(
      self,
      children: [
        ("privateCloudDatabase", privateCloudDatabase),
        ("sharedCloudDatabase", sharedCloudDatabase),
      ],
      displayStyle: .struct
    )
  }
}

@available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
private enum MockCloudContainersKey: DependencyKey {
  static var liveValue: LockIsolated<[String: MockCloudContainer]> {
    LockIsolated<[String: MockCloudContainer]>([:])
  }
  static var testValue: LockIsolated<[String: MockCloudContainer]> {
    LockIsolated<[String: MockCloudContainer]>([:])
  }
}

extension DependencyValues {
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  fileprivate var mockCloudContainers: LockIsolated<[String: MockCloudContainer]> {
    get {
      self[MockCloudContainersKey.self]
    }
    set {
      self[MockCloudContainersKey.self] = newValue
    }
  }
}
