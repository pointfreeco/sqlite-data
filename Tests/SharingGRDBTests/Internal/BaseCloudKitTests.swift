import CloudKit
import SharingGRDB
import SnapshotTesting
import Testing

@Suite(.serialized, .snapshots(record: .failed))
class BaseCloudKitTests: @unchecked Sendable {
  let database: any DatabaseWriter
  private let _syncEngine: any Sendable
  private let _underlyingSyncEngine: any Sendable

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  var syncEngine: SyncEngine {
    _syncEngine as! SyncEngine
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  var underlyingSyncEngine: MockSyncEngine {
    _underlyingSyncEngine as! MockSyncEngine
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  init() async throws {
    let database = try SharingGRDBTests.database()
    let underlyingSyncEngine = MockSyncEngine(state: MockSyncEngineState())
    self.database = database
    self._underlyingSyncEngine = underlyingSyncEngine
    _syncEngine = try SyncEngine(
      defaultSyncEngine: underlyingSyncEngine,
      database: database,
      metadatabaseURL: URL.temporaryDirectory.appending(
        path: "metadatabase.\(UUID().uuidString).sqlite"
      ),
      tables: [Reminder.self, RemindersList.self, User.self]
    )
    try await Task.sleep(for: .seconds(0.1))
    underlyingSyncEngine.assertFetchChangesScopes([.all])
  }

  deinit {
    if #available(iOS 17, macOS 14, tvOS 17, watchOS 10, *) {
      underlyingSyncEngine.assertFetchChangesScopes([])
      underlyingSyncEngine.state.assertPendingDatabaseChanges([])
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([])
    } else {
      Issue.record("Tests must be run on iOS 17+,m macOS 14+, tvOS 17+ and watchOS 10+.")
    }
  }
}
