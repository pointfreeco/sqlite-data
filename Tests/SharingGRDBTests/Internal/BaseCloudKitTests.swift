import CloudKit
import DependenciesTestSupport
import OrderedCollections
import os
import SharingGRDB
import SnapshotTesting
import Testing

@Suite(
  .snapshots(record: .failed),
  .dependency(\.date.now, Date(timeIntervalSince1970: 1234567890))
)
class BaseCloudKitTests: @unchecked Sendable {
  let userDatabase: UserDatabase
  private let _syncEngine: any Sendable

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  var syncEngine: SyncEngine {
    _syncEngine as! SyncEngine
  }

  typealias SendablePrimaryKeyedTable<T> = PrimaryKeyedTable<T> & Sendable

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  init(
    setUpUserDatabase: @Sendable (UserDatabase) async throws -> Void = { _ in }
  ) async throws {
    let testContainerIdentifier = "iCloud.co.pointfree.Testing.\(UUID())"

    self.userDatabase = UserDatabase(
      database: try SharingGRDBTests.database(containerIdentifier: testContainerIdentifier)
    )
    try await setUpUserDatabase(userDatabase)
    let privateDatabase = MockCloudDatabase(databaseScope: .private)
    let sharedDatabase = MockCloudDatabase(databaseScope: .shared)
    _syncEngine = try await SyncEngine(
      container: MockCloudContainer(
        privateCloudDatabase: privateDatabase,
        sharedCloudDatabase: sharedDatabase
      ),
      userDatabase: self.userDatabase,
      metadatabaseURL: URL.metadatabase(containerIdentifier: testContainerIdentifier),
      tables: [
        Reminder.self,
        RemindersList.self,
        Tag.self,
        ReminderTag.self,
        Parent.self,
        ChildWithOnDeleteRestrict.self,
        ChildWithOnDeleteSetNull.self,
        ChildWithOnDeleteSetDefault.self,
      ],
      privateTables: [
        RemindersListPrivate.self
      ]
    )
  }

  deinit {
    if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
      syncEngine.shared.assertFetchChangesScopes([])
      syncEngine.shared.state.assertPendingDatabaseChanges([])
      syncEngine.shared.state.assertPendingRecordZoneChanges([])
      syncEngine.shared.assertAcceptedShareMetadata([])
      syncEngine.private.assertFetchChangesScopes([])
      syncEngine.private.state.assertPendingDatabaseChanges([])
      syncEngine.private.state.assertPendingRecordZoneChanges([])
      syncEngine.private.assertAcceptedShareMetadata([])
    } else {
      Issue.record("Tests must be run on iOS 17+,m macOS 14+, tvOS 17+ and watchOS 10+.")
    }
  }
}

extension SyncEngine {
  var `private`: MockSyncEngine {
    syncEngines.private as! MockSyncEngine
  }
  var shared: MockSyncEngine {
    syncEngines.shared as! MockSyncEngine
  }
  convenience init(
    container: any CloudContainer,
    userDatabase: UserDatabase,
    metadatabaseURL: URL,
    tables: [any PrimaryKeyedTable<UUID>.Type],
    privateTables: [any PrimaryKeyedTable<UUID>.Type] = []
  ) async throws {
    try self.init(
      container: container,
      defaultSyncEngines: { _, syncEngine in
        (
          MockSyncEngine(
            database: container.privateCloudDatabase as! MockCloudDatabase,
            delegate: syncEngine,
            scope: .private,
            state: MockSyncEngineState()
          ),
          MockSyncEngine(
            database: container.sharedCloudDatabase as! MockCloudDatabase,
            delegate: syncEngine,
            scope: .shared,
            state: MockSyncEngineState()
          )
        )
      },
      userDatabase: userDatabase,
      logger: Logger(.disabled),
      metadatabaseURL: metadatabaseURL,
      tables: tables,
      privateTables: privateTables
    )
    try await setUpSyncEngine(userDatabase: userDatabase, metadatabase: metadatabase)?.value
  }
}
