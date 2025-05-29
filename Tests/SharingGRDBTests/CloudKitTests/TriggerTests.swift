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
              ("recordType", "recordName", "zoneName", "ownerName", "parentRecordName", "userModificationDate")
            SELECT
              'reminders',
              "new"."id",
              'co.pointfree.SharingGRDB.defaultZone',
              '__defaultOwner__',
              "new"."remindersListID",
              datetime('subsec')
            ON CONFLICT("recordName") DO NOTHING;
          END
          """,
          [4]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_reminders_metadataUpdates"
          AFTER UPDATE ON "reminders" FOR EACH ROW BEGIN
            INSERT INTO "sharing_grdb_cloudkit_metadata"
              ("recordType", "recordName", "zoneName", "ownerName", "parentRecordName")
            SELECT
              'reminders',
              "new"."id",
              'co.pointfree.SharingGRDB.defaultZone',
              '__defaultOwner__',
              "new"."remindersListID"
            ON CONFLICT("recordName") DO UPDATE SET
              "userModificationDate" = datetime('subsec'),
              "parentRecordName" = "excluded"."parentRecordName";
          END
          """,
          [5]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_reminders_metadataDeletes"
          AFTER DELETE ON "reminders" FOR EACH ROW BEGIN
            DELETE FROM "sharing_grdb_cloudkit_metadata"
            WHERE "recordType" = 'reminders'
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
          CREATE TRIGGER "sharing_grdb_cloudkit_reminders_belongsTo_reminders_onDeleteCascade"
          AFTER DELETE ON "reminders"
          FOR EACH ROW BEGIN
            DELETE FROM "reminders"
            WHERE "parentReminderID" = "old"."id";
          END
          """,
          [9]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_reminders_belongsTo_reminders_onUpdateCascade"
          AFTER UPDATE ON "reminders"
          FOR EACH ROW BEGIN
            UPDATE "reminders"
            SET "parentReminderID" = "new"."id"
            WHERE "parentReminderID" = "old"."id";
          END
          """,
          [10]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_reminders_belongsTo_users_onDeleteSetNull"
          AFTER DELETE ON "users"
          FOR EACH ROW BEGIN
            UPDATE "reminders"
            SET "assignedUserID" = NULL
            WHERE "assignedUserID" = "old"."id";
          END
          """,
          [11]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_reminders_belongsTo_users_onUpdateCascade"
          AFTER UPDATE ON "users"
          FOR EACH ROW BEGIN
            UPDATE "reminders"
            SET "assignedUserID" = "new"."id"
            WHERE "assignedUserID" = "old"."id";
          END
          """,
          [12]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_insert_remindersLists"
          AFTER INSERT ON "remindersLists" FOR EACH ROW BEGIN
            SELECT didUpdate(
              "new"."id",
              'remindersLists'
            )
            WHERE NOT isUpdatingWithServerRecord();
          END
          """,
          [13]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_update_remindersLists"
          AFTER UPDATE ON "remindersLists" FOR EACH ROW BEGIN
            SELECT didUpdate(
              "new"."id",
              'remindersLists'
            )
            WHERE NOT isUpdatingWithServerRecord();
          END
          """,
          [14]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_delete_remindersLists"
          BEFORE DELETE ON "remindersLists" FOR EACH ROW BEGIN
            SELECT willDelete(
              "old"."id",
              'remindersLists'
            )
            WHERE NOT isUpdatingWithServerRecord();
          END
          """,
          [15]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_remindersLists_metadataInserts"
          AFTER INSERT ON "remindersLists" FOR EACH ROW BEGIN
            INSERT INTO "sharing_grdb_cloudkit_metadata"
              ("recordType", "recordName", "zoneName", "ownerName", "parentRecordName", "userModificationDate")
            SELECT
              'remindersLists',
              "new"."id",
              'co.pointfree.SharingGRDB.defaultZone',
              '__defaultOwner__',
              NULL,
              datetime('subsec')
            ON CONFLICT("recordName") DO NOTHING;
          END
          """,
          [16]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_remindersLists_metadataUpdates"
          AFTER UPDATE ON "remindersLists" FOR EACH ROW BEGIN
            INSERT INTO "sharing_grdb_cloudkit_metadata"
              ("recordType", "recordName", "zoneName", "ownerName", "parentRecordName")
            SELECT
              'remindersLists',
              "new"."id",
              'co.pointfree.SharingGRDB.defaultZone',
              '__defaultOwner__',
              NULL
            ON CONFLICT("recordName") DO UPDATE SET
              "userModificationDate" = datetime('subsec'),
              "parentRecordName" = "excluded"."parentRecordName";
          END
          """,
          [17]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_remindersLists_metadataDeletes"
          AFTER DELETE ON "remindersLists" FOR EACH ROW BEGIN
            DELETE FROM "sharing_grdb_cloudkit_metadata"
            WHERE "recordType" = 'remindersLists'
            AND "recordName" = "old"."id";
          END
          """,
          [18]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_insert_users"
          AFTER INSERT ON "users" FOR EACH ROW BEGIN
            SELECT didUpdate(
              "new"."id",
              'users'
            )
            WHERE NOT isUpdatingWithServerRecord();
          END
          """,
          [19]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_update_users"
          AFTER UPDATE ON "users" FOR EACH ROW BEGIN
            SELECT didUpdate(
              "new"."id",
              'users'
            )
            WHERE NOT isUpdatingWithServerRecord();
          END
          """,
          [20]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_delete_users"
          BEFORE DELETE ON "users" FOR EACH ROW BEGIN
            SELECT willDelete(
              "old"."id",
              'users'
            )
            WHERE NOT isUpdatingWithServerRecord();
          END
          """,
          [21]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_users_metadataInserts"
          AFTER INSERT ON "users" FOR EACH ROW BEGIN
            INSERT INTO "sharing_grdb_cloudkit_metadata"
              ("recordType", "recordName", "zoneName", "ownerName", "parentRecordName", "userModificationDate")
            SELECT
              'users',
              "new"."id",
              'co.pointfree.SharingGRDB.defaultZone',
              '__defaultOwner__',
              NULL,
              datetime('subsec')
            ON CONFLICT("recordName") DO NOTHING;
          END
          """,
          [22]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_users_metadataUpdates"
          AFTER UPDATE ON "users" FOR EACH ROW BEGIN
            INSERT INTO "sharing_grdb_cloudkit_metadata"
              ("recordType", "recordName", "zoneName", "ownerName", "parentRecordName")
            SELECT
              'users',
              "new"."id",
              'co.pointfree.SharingGRDB.defaultZone',
              '__defaultOwner__',
              NULL
            ON CONFLICT("recordName") DO UPDATE SET
              "userModificationDate" = datetime('subsec'),
              "parentRecordName" = "excluded"."parentRecordName";
          END
          """,
          [23]: """
          CREATE TRIGGER "sharing_grdb_cloudkit_users_metadataDeletes"
          AFTER DELETE ON "users" FOR EACH ROW BEGIN
            DELETE FROM "sharing_grdb_cloudkit_metadata"
            WHERE "recordType" = 'users'
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
      underlyingSyncEngine.assertFetchChangesScopes([.all])
      let triggersAfterReSetUp = try await database.write { db in
        try #sql("SELECT sql FROM sqlite_temp_master", as: String?.self).fetchAll(db)
      }
      expectNoDifference(triggersAfterReSetUp, triggersAfterSetUp)
    }
  }
}
