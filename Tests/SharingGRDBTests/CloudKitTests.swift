import CloudKit
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import ConcurrencyExtras
import Testing

@Suite(.snapshots(record: .failed))
struct CloudKitTests {
  let database: any DatabaseWriter
  let _syncEngine: any Sendable
  let underlyingSyncEngine: MockSyncEngine
  let underlyingSyncState: MockSyncEngineState

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  var syncEngine: SyncEngine {
    _syncEngine as! SyncEngine
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  init() async throws {
    underlyingSyncState = MockSyncEngineState()
    underlyingSyncEngine = MockSyncEngine(engineState: underlyingSyncState)
    self.database = try SharingGRDBTests.database()
    _syncEngine = SyncEngine(
      defaultSyncEngine: underlyingSyncEngine,
      database: database,
      tables: [Reminder.self, RemindersList.self]
    )
    try await Task.sleep(for: .seconds(0.1))
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func setUpAndTearDown() async throws {
    try await Task.sleep(for: .seconds(0.1))

    try await database.read { db in
      assertInlineSnapshot(
        of: try #sql("SELECT sql FROM sqlite_temp_master", as: String?.self).fetchAll(db),
        as: .customDump
      ) {
        #"""
        [
          [0]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_insert_remindersLists"
          AFTER INSERT ON "remindersLists" FOR EACH ROW BEGIN
            SELECT didUpdate(
              "new"."id",
              'remindersLists'
            )
            WHERE areTriggersEnabled();
          END
          """,
          [1]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_update_remindersLists"
          AFTER UPDATE ON "remindersLists" FOR EACH ROW BEGIN
            SELECT didUpdate(
              "new"."id",
              'remindersLists'
            )
            WHERE areTriggersEnabled();
          END
          """,
          [2]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_delete_remindersLists"
          BEFORE DELETE ON "remindersLists" FOR EACH ROW BEGIN
            SELECT willDelete(
              "old"."id",
              'remindersLists'
            )
            WHERE areTriggersEnabled();
          END
          """,
          [3]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_remindersLists_metadataInserts"
          AFTER INSERT ON "remindersLists" FOR EACH ROW BEGIN
            INSERT INTO "sharing_grdb_cloudkit_metadata"
              ("zoneName", "recordName", "userModificationDate")
            SELECT
              'remindersLists',
              "new"."id",
              datetime('subsec')
            WHERE areTriggersEnabled()
            ON CONFLICT("zoneName", "recordName") DO NOTHING;
          END
          """,
          [4]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_remindersLists_metadataUpdates"
          AFTER UPDATE ON "remindersLists" FOR EACH ROW BEGIN
            INSERT INTO "sharing_grdb_cloudkit_metadata"
              ("zoneName", "recordName")
            SELECT 'remindersLists', "new"."id"
            WHERE areTriggersEnabled()
            ON CONFLICT("zoneName", "recordName") DO UPDATE SET
              "userModificationDate" = datetime('subsec');
          END
          """,
          [5]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_insert_reminders"
          AFTER INSERT ON "reminders" FOR EACH ROW BEGIN
            SELECT didUpdate(
              "new"."id",
              'reminders'
            )
            WHERE areTriggersEnabled();
          END
          """,
          [6]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_update_reminders"
          AFTER UPDATE ON "reminders" FOR EACH ROW BEGIN
            SELECT didUpdate(
              "new"."id",
              'reminders'
            )
            WHERE areTriggersEnabled();
          END
          """,
          [7]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_delete_reminders"
          BEFORE DELETE ON "reminders" FOR EACH ROW BEGIN
            SELECT willDelete(
              "old"."id",
              'reminders'
            )
            WHERE areTriggersEnabled();
          END
          """,
          [8]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_reminders_metadataInserts"
          AFTER INSERT ON "reminders" FOR EACH ROW BEGIN
            INSERT INTO "sharing_grdb_cloudkit_metadata"
              ("zoneName", "recordName", "userModificationDate")
            SELECT
              'reminders',
              "new"."id",
              datetime('subsec')
            WHERE areTriggersEnabled()
            ON CONFLICT("zoneName", "recordName") DO NOTHING;
          END
          """,
          [9]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_reminders_metadataUpdates"
          AFTER UPDATE ON "reminders" FOR EACH ROW BEGIN
            INSERT INTO "sharing_grdb_cloudkit_metadata"
              ("zoneName", "recordName")
            SELECT 'reminders', "new"."id"
            WHERE areTriggersEnabled()
            ON CONFLICT("zoneName", "recordName") DO UPDATE SET
              "userModificationDate" = datetime('subsec');
          END
          """,
          [10]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_reminders_belongsTo_remindersLists_onDeleteCascade"
          AFTER DELETE ON "remindersLists"
          FOR EACH ROW BEGIN
            DELETE FROM "reminders"
            WHERE "remindersListID" = "old"."id";
          END
          """
        ]
        """#
      }
    }

    try await syncEngine.tearDownSyncEngine()
    try await database.read { db in
      assertInlineSnapshot(
        of: try #sql("SELECT sql FROM sqlite_temp_master", as: String?.self).fetchAll(db),
        as: .customDump
      ) {
        """
        []
        """
      }
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func insert() async throws {
    try await database.write { db in
      try RemindersList
        .insert(RemindersList.Draft(title: "Personal"))
        .execute(db)
    }
    try await Task.sleep(for: .seconds(1))
    #expect(underlyingSyncState.pendingRecordZoneChanges == [])
  }

  @Test func inMemoryAttachment() throws {
    print(#function)
    let d1 = try DatabaseQueue(named: "d1")
    let d1_ = try DatabaseQueue(named: "d1")
    let d2 = try DatabaseQueue(named: "d2")

    try d1.write { db in
      try #sql("create table t1 (id integer)").execute(db)
      try #sql("insert into t1 (id) values (1), (2), (3)").execute(db)
    }
    try d2.write { db in
      try #sql("create table t2 (id integer)").execute(db)
      try #sql("insert into t2 (id) values (10), (20), (30)").execute(db)
    }
    try d1_.read { db in
      try #expect(#sql("select id from t1", as: Int.self).fetchAll(db) == [1, 2, 3])
    }
    try d2.read { db in
      try #expect(#sql("select id from t2", as: Int.self).fetchAll(db) == [10, 20, 30])
    }

    try d2.write { db in
      try #sql("attach database 'file:d1?mode=memory&cache=shared' as 'd1'").execute(db)
    }
    try d2.read { db in
      try #expect(#sql("select id from d1.t1", as: Int.self).fetchAll(db) == [1, 2, 3])
      try #expect(#sql("select id from t2", as: Int.self).fetchAll(db) == [10, 20, 30])
    }
    try d2.read { db in
      try #sql("DETACH DATABASE d1").execute(db)
    }
    try d2.write { db in
      withKnownIssue {
        try #expect(#sql("select id from d1.t1", as: Int.self).fetchAll(db) == [1, 2, 3])
      }
      try #expect(#sql("select id from t2", as: Int.self).fetchAll(db) == [10, 20, 30])
    }
  }

  @Test func detatchFromWriteProblem() throws {
    print(#function)
    let d2 = try DatabaseQueue(named: "d2")
    try d2.write { db in
      try #sql("attach database 'file:d1?mode=memory&cache=shared' as 'd1'").execute(db)
    }
    try d2.write { db in
      try #sql("DETACH DATABASE d1").execute(db)
    }
  }
}

@Table private struct Reminder: Identifiable {
  let id: Int
  var title = ""
  var remindersListID: RemindersList.ID
}
@Table private struct RemindersList: Identifiable {
  let id: Int
  var title = ""
}

private func database() throws -> any DatabaseWriter {
  var configuration = Configuration()
  configuration.foreignKeysEnabled = false
  configuration.prepareDatabase { db in
    db.trace { print($0) }
  }
  let database = try DatabaseQueue(configuration: configuration)
  var migrator = DatabaseMigrator()
  migrator.registerMigration("Create tables") { db in
    try #sql(
      """
      CREATE TABLE "remindersLists" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "title" TEXT NOT NULL
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "title" TEXT NOT NULL,
        "remindersListID" INTEGER NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
  }
  try migrator.migrate(database)
  return database
}

final class MockSyncEngine: CKSyncEngineProtocol {
  let _engineState: LockIsolated<any CKSyncEngineStateProtocol>
  init(engineState: any CKSyncEngineStateProtocol) {
    self._engineState = LockIsolated(engineState)
  }
  var engineState: any CKSyncEngineStateProtocol {
    _engineState.withValue(\.self)
  }
  func fetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws {
  }
}

final class MockSyncEngineState: CKSyncEngineStateProtocol {
  private let _pendingRecordZoneChanges = LockIsolated<[CKSyncEngine.PendingRecordZoneChange]>([])
  private let _pendingDatabaseChanges = LockIsolated<[CKSyncEngine.PendingDatabaseChange]>([])

  var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] {
    _pendingRecordZoneChanges.withValue(\.self)
  }
  var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] {
    _pendingDatabaseChanges.withValue(\.self)
  }

  func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
    self._pendingRecordZoneChanges.withValue {
      $0.append(contentsOf: pendingRecordZoneChanges)
    }
  }
  func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
    self._pendingRecordZoneChanges.withValue {
      $0.removeAll(where: pendingRecordZoneChanges.contains)
    }
  }
  func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
    self._pendingDatabaseChanges.withValue {
      $0.append(contentsOf: pendingDatabaseChanges)
    }
  }
  func remove(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
    self._pendingDatabaseChanges.withValue {
      $0.removeAll(where: pendingDatabaseChanges.contains)
    }
  }
}
