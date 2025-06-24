import CloudKit
import SharingGRDB
import SnapshotTesting
import Testing

@Suite(.snapshots(record: .failed))
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

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  init() async throws {
    let testContainerIdentifier = "iCloud.co.pointfree.Testing.\(UUID())"

    let database = try SharingGRDBTests.database(containerIdentifier: testContainerIdentifier)
    let privateSyncEngine = MockSyncEngine(scope: .private, state: MockSyncEngineState())
    let sharedSyncEngine = MockSyncEngine(scope: .shared, state: MockSyncEngineState())
    self.database = database
    _privateSyncEngine = privateSyncEngine
    _sharedSyncEngine = sharedSyncEngine
    _syncEngine = try SyncEngine(
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
    try await Task.sleep(for: .seconds(0.1))
    privateSyncEngine.assertFetchChangesScopes([.all])
    sharedSyncEngine.assertFetchChangesScopes([.all])
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
