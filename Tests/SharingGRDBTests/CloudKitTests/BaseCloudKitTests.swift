import CloudKit
import SharingGRDB
import SnapshotTesting
import Testing

@Suite(.snapshots(record: .failed))
class BaseCloudKitTests: @unchecked Sendable {
  let database: any DatabaseWriter
  let _syncEngine: any Sendable
  let underlyingSyncEngine: MockSyncEngine

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  var syncEngine: SyncEngine {
    _syncEngine as! SyncEngine
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  init() async throws {
    let database = try SharingGRDBTests.database()
    let underlyingSyncEngine = MockSyncEngine(state: MockSyncEngineState())
    self.database = database
    self.underlyingSyncEngine = underlyingSyncEngine
    _syncEngine = SyncEngine(
      defaultSyncEngine: underlyingSyncEngine,
      database: database,
      metadatabaseURL: URL.temporaryDirectory.appending(
        path: "metadatabase.\(UUID().uuidString).sqlite"
      ),
      tables: [Reminder.self, RemindersList.self]
    )
    try await Task.sleep(for: .seconds(0.1))
  }

  deinit {
    underlyingSyncEngine.state.assertPendingDatabaseChanges([])
    underlyingSyncEngine.state.assertPendingRecordZoneChanges([])
  }
}
