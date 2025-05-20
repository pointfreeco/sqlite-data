import CloudKit
import ConcurrencyExtras
import CustomDump
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

@Suite(.snapshots(record: .failed))
final class CloudKitTests: Sendable {
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
    let database = try SharingGRDBTests.database()
    let underlyingSyncState = MockSyncEngineState()
    let underlyingSyncEngine = MockSyncEngine(engineState: underlyingSyncState)
    self.database = database
    self.underlyingSyncState = underlyingSyncState
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
    underlyingSyncState.assertPendingDatabaseChanges([])
    underlyingSyncState.assertPendingRecordZoneChanges([])
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func setUpAndTearDown() async throws {
    var sqls = try await database.write { db in
      try #sql("SELECT sql FROM sqlite_temp_master", as: String?.self).fetchAll(db)
    }
    assertInlineSnapshot(of: sqls, as: .customDump) {
      #"""
      [
        [0]: """
        CREATE TRIGGER "sharing_grdb_cloudkit_insert_reminders"
        AFTER INSERT ON "reminders" FOR EACH ROW BEGIN
          SELECT didUpdate(
            "new"."id",
            'reminders'
          )
          WHERE areTriggersEnabled();
        END
        """,
        [1]: """
        CREATE TRIGGER "sharing_grdb_cloudkit_update_reminders"
        AFTER UPDATE ON "reminders" FOR EACH ROW BEGIN
          SELECT didUpdate(
            "new"."id",
            'reminders'
          )
          WHERE areTriggersEnabled();
        END
        """,
        [2]: """
        CREATE TRIGGER "sharing_grdb_cloudkit_delete_reminders"
        BEFORE DELETE ON "reminders" FOR EACH ROW BEGIN
          SELECT willDelete(
            "old"."id",
            'reminders'
          )
          WHERE areTriggersEnabled();
        END
        """,
        [3]: """
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
        [4]: """
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
        [5]: """
        CREATE TRIGGER "sharing_grdb_cloudkit_reminders_metadataDeletes"
        AFTER DELETE ON "reminders" FOR EACH ROW BEGIN
          DELETE FROM "sharing_grdb_cloudkit_metadata"
          WHERE areTriggersEnabled()
          AND "zoneName" = 'reminders'
          AND "recordName" = "old"."id";
        END
        """,
        [6]: """
        CREATE TRIGGER "sharing_grdb_cloudkit_reminders_belongsTo_remindersLists_onDeleteCascade"
        AFTER DELETE ON "remindersLists"
        FOR EACH ROW BEGIN
          DELETE FROM "reminders"
          WHERE "remindersListID" = "old"."id";
        END
        """,
        [7]: """
        CREATE TRIGGER "sharing_grdb_cloudkit_insert_remindersLists"
        AFTER INSERT ON "remindersLists" FOR EACH ROW BEGIN
          SELECT didUpdate(
            "new"."id",
            'remindersLists'
          )
          WHERE areTriggersEnabled();
        END
        """,
        [8]: """
        CREATE TRIGGER "sharing_grdb_cloudkit_update_remindersLists"
        AFTER UPDATE ON "remindersLists" FOR EACH ROW BEGIN
          SELECT didUpdate(
            "new"."id",
            'remindersLists'
          )
          WHERE areTriggersEnabled();
        END
        """,
        [9]: """
        CREATE TRIGGER "sharing_grdb_cloudkit_delete_remindersLists"
        BEFORE DELETE ON "remindersLists" FOR EACH ROW BEGIN
          SELECT willDelete(
            "old"."id",
            'remindersLists'
          )
          WHERE areTriggersEnabled();
        END
        """,
        [10]: """
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
        [11]: """
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
        [12]: """
        CREATE TRIGGER "sharing_grdb_cloudkit_remindersLists_metadataDeletes"
        AFTER DELETE ON "remindersLists" FOR EACH ROW BEGIN
          DELETE FROM "sharing_grdb_cloudkit_metadata"
          WHERE areTriggersEnabled()
          AND "zoneName" = 'remindersLists'
          AND "recordName" = "old"."id";
        END
        """
      ]
      """#
    }

    try await syncEngine.tearDownSyncEngine()
    sqls = try await database.write { db in
      try #sql("SELECT sql FROM sqlite_temp_master", as: String?.self).fetchAll(db)
    }
    assertInlineSnapshot(of: sqls, as: .customDump) {
      """
      []
      """
    }
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func tearDownAndReSetUp() async throws {
    try await syncEngine.tearDownSyncEngine()
    try await syncEngine.setUpSyncEngine()
    // TODO: it would be nice if `setUpSyncEngine` was async
    try await Task.sleep(for: .seconds(0.1))

    try await database.write { db in
      try db.seed {
        RemindersList(id: UUID(1), title: "Personal")
      }
    }
    underlyingSyncState.assertPendingRecordZoneChanges([
      .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self))
    ])

    let record = CKRecord(
      recordType: "remindersLists",
      recordID: CKRecord.ID(UUID(1), in: RemindersList.self)
    )
    await syncEngine.handleFetchedRecordZoneChanges(
      modifications: [record],
      deletions: []
    )
    expectNoDifference(
      try { try database.read { db in try RemindersList.find(UUID(1)).fetchOne(db) } }(),
      RemindersList(id: UUID(1), title: "Personal")
    )

    let metadata =
      try await database.write { db in
        try Metadata.find(recordID: record.recordID).fetchOne(db)
      }
    #expect(metadata != nil)
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func insertUpdateDelete() throws {
    try database.write { db in
      try RemindersList
        .insert(RemindersList(id: UUID(1), title: "Personal"))
        .execute(db)
    }
    underlyingSyncState.assertPendingRecordZoneChanges([
      .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self))
    ])
    try database.write { db in
      try RemindersList
        .find(UUID(1))
        .update { $0.title = "Work" }
        .execute(db)
    }
    underlyingSyncState.assertPendingRecordZoneChanges([
      .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self))
    ])
    try database.write { db in
      try RemindersList
        .find(UUID(1))
        .delete()
        .execute(db)
    }
    underlyingSyncState.assertPendingRecordZoneChanges([
      .deleteRecord(CKRecord.ID(UUID(1), in: RemindersList.self))
    ])
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func deleteCascade() throws {
    try database.write { db in
      try db.seed {
        RemindersList(id: UUID(1), title: "Personal")
        Reminder(id: UUID(1), title: "Groceries", remindersListID: UUID(1))
        Reminder(id: UUID(2), title: "Walk", remindersListID: UUID(1))
        Reminder(id: UUID(3), title: "Haircut", remindersListID: UUID(1))
      }
    }
    underlyingSyncState.assertPendingRecordZoneChanges([
      .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self)),
      .saveRecord(CKRecord.ID(UUID(1), in: Reminder.self)),
      .saveRecord(CKRecord.ID(UUID(2), in: Reminder.self)),
      .saveRecord(CKRecord.ID(UUID(3), in: Reminder.self)),
    ])
    try database.write { db in
      try RemindersList.find(UUID(1)).delete().execute(db)
    }
    underlyingSyncState.assertPendingRecordZoneChanges([
      .deleteRecord(CKRecord.ID(UUID(1), in: RemindersList.self)),
      .deleteRecord(CKRecord.ID(UUID(1), in: Reminder.self)),
      .deleteRecord(CKRecord.ID(UUID(2), in: Reminder.self)),
      .deleteRecord(CKRecord.ID(UUID(3), in: Reminder.self)),
    ])
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func remoteServerRecordUpdate() async throws {
    try await database.write { db in
      try db.seed {
        RemindersList(id: UUID(1), title: "Personal")
      }
    }
    underlyingSyncState.assertPendingRecordZoneChanges([
      .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self))
    ])

    let record = CKRecord(
      recordType: "remindersLists",
      recordID: CKRecord.ID(UUID(1), in: RemindersList.self)
    )
    // TODO: Should we omit primary key from `encryptedValues` since it already exists on recordName?
    record.encryptedValues[RemindersList.columns.id.name] = UUID(1).uuidString
    record.encryptedValues[RemindersList.columns.title.name] = "Work"
    record.userModificationDate = Date.distantFuture
    await syncEngine.handleFetchedRecordZoneChanges(
      modifications: [record],
      deletions: []
    )
    expectNoDifference(
      try { try database.read { db in try RemindersList.find(UUID(1)).fetchOne(db) } }(),
      RemindersList(id: UUID(1), title: "Work")
    )

    let metadata = try #require(
      try await database.write { db in
        try Metadata.find(recordID: record.recordID).fetchOne(db)
      }
    )
    expectNoDifference(record, metadata.lastKnownServerRecord)
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func remoteServerRecordDeleted() async throws {
    try await database.write { db in
      try db.seed {
        RemindersList(id: UUID(1), title: "Personal")
      }
    }
    underlyingSyncState.assertPendingRecordZoneChanges([
      .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self))
    ])

    let record = CKRecord(
      recordType: "remindersLists",
      recordID: CKRecord.ID(UUID(1), in: RemindersList.self)
    )
    await syncEngine.handleFetchedRecordZoneChanges(
      modifications: [],
      deletions: [(record.recordID, record.recordType)]
    )
    #expect(
      try { try database.read { db in try RemindersList.find(UUID(1)).fetchCount(db) } }()
        == 0
    )
    let metadata = try await database.write { db in
      try Metadata.find(recordID: record.recordID).fetchOne(db)
    }
    #expect(metadata == nil)

    // TODO: Do not enqueue a pending zone change when the delete came the server
    withKnownIssue {
      underlyingSyncState.assertPendingRecordZoneChanges([])
    }
  }
}

extension CKRecord.ID {
  convenience init<T: PrimaryKeyedTable>(
    _ id: T.TableColumns.PrimaryKey,
    in table: T.Type
  )
  where T.TableColumns.PrimaryKey == UUID {
    self.init(
      recordName: id.uuidString,
      zoneID: CKRecordZone.ID(zoneName: T.tableName)
    )
  }
}

@Table private struct Reminder: Equatable, Identifiable {
  let id: UUID
  var title = ""
  var remindersListID: RemindersList.ID
}
@Table private struct RemindersList: Equatable, Identifiable {
  let id: UUID
  var title = ""
}

private func database() throws -> DatabasePool {
  var configuration = Configuration()
  configuration.foreignKeysEnabled = false
  let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
  let database = try DatabasePool(path: url.path(), configuration: configuration)
  var migrator = DatabaseMigrator()
  migrator.registerMigration("Create tables") { db in
    try #sql(
      """
      CREATE TABLE "remindersLists" (
        "id" TEXT PRIMARY KEY DEFAULT (uuid()),
        "title" TEXT NOT NULL
      ) STRICT
      """
    )
    .execute(db)
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" TEXT PRIMARY KEY DEFAULT (uuid()),
        "title" TEXT NOT NULL,
        "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
      ) STRICT
      """
    )
    .execute(db)
  }
  try migrator.migrate(database)
  return database
}
