import CustomDump
import CloudKit

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

  package func shareMetadata(for url: URL, shouldFetchRootRecord: Bool) async throws -> CKShare.Metadata {
    fatalError()
  }

  package func accept(_ metadata: CKShare.Metadata) async throws -> CKShare {
    fatalError()
  }

  package static func createContainer(identifier containerIdentifier: String) -> MockCloudContainer {
    @Dependency(\.mockCloudContainers) var mockCloudContainers
    return mockCloudContainers.withValue { storage in
      let container: MockCloudContainer
      if let existingContainer = storage[containerIdentifier] {
        container = existingContainer
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
    Mirror.init(
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
private enum MockCloudContainersKey: TestDependencyKey {
  static var testValue: LockIsolated<[String: MockCloudContainer]> {
    LockIsolated<[String: MockCloudContainer]>([:])
  }
}

extension DependencyValues {
  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  package var mockCloudContainers: LockIsolated<[String: MockCloudContainer]> {
    get {
      self[MockCloudContainersKey.self]
    }
    set {
      self[MockCloudContainersKey.self] = newValue
    }
  }
}
