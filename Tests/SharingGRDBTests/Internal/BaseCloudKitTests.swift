import CloudKit
import DependenciesTestSupport
import SharingGRDB
import SnapshotTesting
import Testing

@Suite(
  .snapshots(record: .failed),
  .dependency(\.date.now, Date(timeIntervalSince1970: 1234567890))
)
class BaseCloudKitTests: @unchecked Sendable {
  let database: any DatabaseWriter
  private let _syncEngine: any Sendable
  private let _privateSyncEngine: any Sendable
  private let _sharedSyncEngine: any Sendable

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  var syncEngine: SyncEngine {
    _syncEngine as! SyncEngine
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  var privateSyncEngine: MockSyncEngine {
    _privateSyncEngine as! MockSyncEngine
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  var sharedSyncEngine: MockSyncEngine {
    _sharedSyncEngine as! MockSyncEngine
  }

  typealias SendablePrimaryKeyedTable<T> = PrimaryKeyedTable<T> & Sendable

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  init(seeds: [any SendablePrimaryKeyedTable<UUID>] = []) async throws {
    let testContainerIdentifier = "iCloud.co.pointfree.Testing.\(UUID())"

    let database = try SharingGRDBTests.database(containerIdentifier: testContainerIdentifier)
    self.database = database
    try { [seeds] in
      try database.write { db in
        try db.seed { seeds }
      }
    }()
    let privateSyncEngine = MockSyncEngine(
      database: MockCloudDatabase(),
      scope: .private,
      state: MockSyncEngineState()
    )
    let sharedSyncEngine = MockSyncEngine(
      database: MockCloudDatabase(),
      scope: .shared,
      state: MockSyncEngineState()
    )
    _privateSyncEngine = privateSyncEngine
    _sharedSyncEngine = sharedSyncEngine
    _syncEngine = try await SyncEngine(
      container: MockCloudContainer(
        privateCloudDatabase: privateSyncEngine.database,
        sharedCloudDatabase: sharedSyncEngine.database
      ),
      privateSyncEngine: privateSyncEngine,
      sharedSyncEngine: sharedSyncEngine,
      database: database,
      metadatabaseURL: URL.metadatabase(containerIdentifier: testContainerIdentifier),
      tables: [
        Reminder.self,
        RemindersList.self,
        Tag.self,
        ReminderTag.self,
        User.self,
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
      sharedSyncEngine.assertFetchChangesScopes([])
      sharedSyncEngine.state.assertPendingDatabaseChanges([])
      sharedSyncEngine.state.assertPendingRecordZoneChanges([])
      sharedSyncEngine.assertAcceptedShareMetadata([])
      privateSyncEngine.assertFetchChangesScopes([])
      privateSyncEngine.state.assertPendingDatabaseChanges([])
      privateSyncEngine.state.assertPendingRecordZoneChanges([])
      privateSyncEngine.assertAcceptedShareMetadata([])
    } else {
      Issue.record("Tests must be run on iOS 17+,m macOS 14+, tvOS 17+ and watchOS 10+.")
    }
  }
}
