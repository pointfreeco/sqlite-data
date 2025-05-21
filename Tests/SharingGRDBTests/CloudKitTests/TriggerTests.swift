import CloudKit
import CustomDump
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  final class TriggerTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func setUpAndTearDown() async throws {
      let triggersAfterSetUp = try await database.write { db in
        try #sql("SELECT sql FROM sqlite_temp_master", as: String?.self).fetchAll(db)
      }
      assertInlineSnapshot(of: triggersAfterSetUp, as: .customDump) {
        #"""
        [
          [0]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_insert_reminders"
          AFTER INSERT ON "reminders" FOR EACH ROW BEGIN
            SELECT didUpdate(
              "new"."id",
              'reminders'
            )
            WHERE NOT isUpdatingWithServerRecord();
          END
          """,
          [1]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_update_reminders"
          AFTER UPDATE ON "reminders" FOR EACH ROW BEGIN
            SELECT didUpdate(
              "new"."id",
              'reminders'
            )
            WHERE NOT isUpdatingWithServerRecord();
          END
          """,
          [2]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_delete_reminders"
          BEFORE DELETE ON "reminders" FOR EACH ROW BEGIN
            SELECT willDelete(
              "old"."id",
              'reminders'
            )
            WHERE NOT isUpdatingWithServerRecord();
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
            ON CONFLICT("zoneName", "recordName") DO NOTHING;
          END
          """,
          [4]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_reminders_metadataUpdates"
          AFTER UPDATE ON "reminders" FOR EACH ROW BEGIN
            INSERT INTO "sharing_grdb_cloudkit_metadata"
              ("zoneName", "recordName")
            SELECT
              'reminders',
              "new"."id"
            ON CONFLICT("zoneName", "recordName") DO UPDATE SET
              "userModificationDate" = datetime('subsec');
          END
          """,
          [5]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_reminders_metadataDeletes"
          AFTER DELETE ON "reminders" FOR EACH ROW BEGIN
            DELETE FROM "sharing_grdb_cloudkit_metadata"
            WHERE "zoneName" = 'reminders'
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
          CREATE TRIGGER "sharing_grdb_cloudkit_reminders_belongsTo_remindersLists_onUpdateCascade"
          AFTER UPDATE ON "remindersLists"
          FOR EACH ROW BEGIN
            UPDATE "reminders"
            SET "remindersListID" = "new"."id"
            WHERE "remindersListID" = "old"."id";
          END
          """,
          [8]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_reminders_belongsTo_reminders_onDeleteSetNull"
          AFTER DELETE ON "reminders"
          FOR EACH ROW BEGIN
            UPDATE "reminders"
            SET "parentReminderID" = NULL
            WHERE "parentReminderID" = "old"."id";
          END
          """,
          [9]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_insert_remindersLists"
          AFTER INSERT ON "remindersLists" FOR EACH ROW BEGIN
            SELECT didUpdate(
              "new"."id",
              'remindersLists'
            )
            WHERE NOT isUpdatingWithServerRecord();
          END
          """,
          [10]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_update_remindersLists"
          AFTER UPDATE ON "remindersLists" FOR EACH ROW BEGIN
            SELECT didUpdate(
              "new"."id",
              'remindersLists'
            )
            WHERE NOT isUpdatingWithServerRecord();
          END
          """,
          [11]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_delete_remindersLists"
          BEFORE DELETE ON "remindersLists" FOR EACH ROW BEGIN
            SELECT willDelete(
              "old"."id",
              'remindersLists'
            )
            WHERE NOT isUpdatingWithServerRecord();
          END
          """,
          [12]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_remindersLists_metadataInserts"
          AFTER INSERT ON "remindersLists" FOR EACH ROW BEGIN
            INSERT INTO "sharing_grdb_cloudkit_metadata"
              ("zoneName", "recordName", "userModificationDate")
            SELECT
              'remindersLists',
              "new"."id",
              datetime('subsec')
            ON CONFLICT("zoneName", "recordName") DO NOTHING;
          END
          """,
          [13]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_remindersLists_metadataUpdates"
          AFTER UPDATE ON "remindersLists" FOR EACH ROW BEGIN
            INSERT INTO "sharing_grdb_cloudkit_metadata"
              ("zoneName", "recordName")
            SELECT
              'remindersLists',
              "new"."id"
            ON CONFLICT("zoneName", "recordName") DO UPDATE SET
              "userModificationDate" = datetime('subsec');
          END
          """,
          [14]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_remindersLists_metadataDeletes"
          AFTER DELETE ON "remindersLists" FOR EACH ROW BEGIN
            DELETE FROM "sharing_grdb_cloudkit_metadata"
            WHERE "zoneName" = 'remindersLists'
            AND "recordName" = "old"."id";
          END
          """
        ]
        """#
      }

      try await syncEngine.tearDownSyncEngine()
      let triggersAfterTearDown = try await database.write { db in
        try #sql("SELECT sql FROM sqlite_temp_master", as: String?.self).fetchAll(db)
      }
      assertInlineSnapshot(of: triggersAfterTearDown, as: .customDump) {
        """
        []
        """
      }

      try await syncEngine.setUpSyncEngine()
      try await Task.sleep(for: .seconds(0.1))
      underlyingSyncEngine.assertFetchChangesScopes([
        .zoneIDs([
          CKRecordZone.ID(RemindersList.self),
          CKRecordZone.ID(Reminder.self),
        ])
      ])
      let triggersAfterReSetUp = try await database.write { db in
        try #sql("SELECT sql FROM sqlite_temp_master", as: String?.self).fetchAll(db)
      }
      expectNoDifference(triggersAfterReSetUp, triggersAfterSetUp)
    }
  }
}
