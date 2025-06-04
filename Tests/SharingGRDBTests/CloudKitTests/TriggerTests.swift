import CloudKit
import CustomDump
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  final class TriggerTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func triggers() async throws {
      let triggersAfterSetUp = try await database.write { db in
        try #sql("SELECT sql FROM sqlite_temp_master", as: String?.self).fetchAll(db)
      }
      assertInlineSnapshot(of: triggersAfterSetUp, as: .customDump) {
        #"""
        [
          [0]: """
          CREATE TRIGGER "sqlitedata_icloud_metadata_inserts"
          AFTER INSERT ON "sqlitedata_icloud_metadata"
          FOR EACH ROW 
          BEGIN
            SELECT 
              sqlitedata_icloud_didUpdate(
                "new"."recordName",
                "new"."zoneName",
                "new"."ownerName"
              )
            WHERE NOT sqlitedata_icloud_isUpdatingWithServerRecord();
          END
          """,
          [1]: """
          CREATE TRIGGER "sqlitedata_icloud_metadata_updates"
          AFTER UPDATE ON "sqlitedata_icloud_metadata"
          FOR EACH ROW 
          BEGIN
            SELECT 
              sqlitedata_icloud_didUpdate(
                "new"."recordName",
                "new"."zoneName",
                "new"."ownerName"
              )
            WHERE NOT sqlitedata_icloud_isUpdatingWithServerRecord()
          ;
          END
          """,
          [2]: """
          CREATE TRIGGER "sqlitedata_icloud_metadata_deletes"
          BEFORE DELETE ON "sqlitedata_icloud_metadata"
          FOR EACH ROW 
          BEGIN
            SELECT 
              sqlitedata_icloud_willDelete(
                "old"."recordName",
                "old"."zoneName",
                "old"."ownerName"
              )
            WHERE NOT sqlitedata_icloud_isUpdatingWithServerRecord();
          END
          """,
          [3]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_metadataInserts"
          AFTER INSERT ON "reminders" FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
              (
                "recordType",
                "recordName",
                "zoneName",
                "ownerName",
                "parentRecordName",
                "userModificationDate"
              )
            SELECT
              'reminders',
              "new"."id",
              coalesce(
                "sqlitedata_icloud_metadata"."zoneName", 
                sqlitedata_icloud_getZoneName(), 
                'co.pointfree.SQLiteData.defaultZone'
              ),
              coalesce(
                "sqlitedata_icloud_metadata"."ownerName", 
                sqlitedata_icloud_getOwnerName(), 
                '__defaultOwner__'
              ),
              "new"."remindersListID" AS "foreignKey",
              datetime('subsec')
            FROM (SELECT 1) 
            LEFT JOIN "sqlitedata_icloud_metadata" ON "sqlitedata_icloud_metadata"."recordName" = "foreignKey"
            ON CONFLICT("recordName") DO NOTHING;
          END
          """,
          [4]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_metadataUpdates"
          AFTER UPDATE ON "reminders" FOR EACH ROW BEGIN
            UPDATE "sqlitedata_icloud_metadata"
            SET
              "recordName" = "new"."id",
              "userModificationDate" = datetime('subsec'),
              "parentRecordName" = "new"."remindersListID"
            WHERE "recordName" = "old"."id";
          END
          """,
          [5]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_metadataDeletes"
          AFTER DELETE ON "reminders" FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE "recordName" = "old"."id";
          END
          """,
          [6]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_belongsTo_remindersLists_onDeleteCascade"
          AFTER DELETE ON "remindersLists"
          FOR EACH ROW BEGIN
            DELETE FROM "reminders"
            WHERE "remindersListID" = "old"."id";
          END
          """,
          [7]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_belongsTo_remindersLists_onUpdateCascade"
          AFTER UPDATE ON "remindersLists"
          FOR EACH ROW BEGIN
            UPDATE "reminders"
            SET "remindersListID" = "new"."id"
            WHERE "remindersListID" = "old"."id";
          END
          """,
          [8]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_belongsTo_reminders_onDeleteRestrict"
          AFTER DELETE ON "reminders"
          FOR EACH ROW BEGIN
            SELECT RAISE(ABORT, 'FOREIGN KEY constraint failed')
            FROM "reminders"
            WHERE "parentReminderID" = "old"."id";
          END
          """,
          [9]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_belongsTo_reminders_onUpdateRestrict"
          AFTER UPDATE ON "reminders"
          FOR EACH ROW BEGIN
            SELECT RAISE(ABORT, 'FOREIGN KEY constraint failed')
            FROM "reminders"
            WHERE "parentReminderID" = "old"."id";
          END
          """,
          [10]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_belongsTo_users_onDeleteSetNull"
          AFTER DELETE ON "users"
          FOR EACH ROW BEGIN
            UPDATE "reminders"
            SET "assignedUserID" = NULL
            WHERE "assignedUserID" = "old"."id";
          END
          """,
          [11]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_belongsTo_users_onUpdateCascade"
          AFTER UPDATE ON "users"
          FOR EACH ROW BEGIN
            UPDATE "reminders"
            SET "assignedUserID" = "new"."id"
            WHERE "assignedUserID" = "old"."id";
          END
          """,
          [12]: """
          CREATE TRIGGER "sqlitedata_icloud_remindersLists_metadataInserts"
          AFTER INSERT ON "remindersLists" FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
              (
                "recordType",
                "recordName",
                "zoneName",
                "ownerName",
                "parentRecordName",
                "userModificationDate"
              )
            SELECT
              'remindersLists',
              "new"."id",
              coalesce(
                "sqlitedata_icloud_metadata"."zoneName", 
                sqlitedata_icloud_getZoneName(), 
                'co.pointfree.SQLiteData.defaultZone'
              ),
              coalesce(
                "sqlitedata_icloud_metadata"."ownerName", 
                sqlitedata_icloud_getOwnerName(), 
                '__defaultOwner__'
              ),
              NULL AS "foreignKey",
              datetime('subsec')
            FROM (SELECT 1) 
            LEFT JOIN "sqlitedata_icloud_metadata" ON "sqlitedata_icloud_metadata"."recordName" = "foreignKey"
            ON CONFLICT("recordName") DO NOTHING;
          END
          """,
          [13]: """
          CREATE TRIGGER "sqlitedata_icloud_remindersLists_metadataUpdates"
          AFTER UPDATE ON "remindersLists" FOR EACH ROW BEGIN
            UPDATE "sqlitedata_icloud_metadata"
            SET
              "recordName" = "new"."id",
              "userModificationDate" = datetime('subsec'),
              "parentRecordName" = NULL
            WHERE "recordName" = "old"."id";
          END
          """,
          [14]: """
          CREATE TRIGGER "sqlitedata_icloud_remindersLists_metadataDeletes"
          AFTER DELETE ON "remindersLists" FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE "recordName" = "old"."id";
          END
          """,
          [15]: """
          CREATE TRIGGER "sqlitedata_icloud_users_metadataInserts"
          AFTER INSERT ON "users" FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
              (
                "recordType",
                "recordName",
                "zoneName",
                "ownerName",
                "parentRecordName",
                "userModificationDate"
              )
            SELECT
              'users',
              "new"."id",
              coalesce(
                "sqlitedata_icloud_metadata"."zoneName", 
                sqlitedata_icloud_getZoneName(), 
                'co.pointfree.SQLiteData.defaultZone'
              ),
              coalesce(
                "sqlitedata_icloud_metadata"."ownerName", 
                sqlitedata_icloud_getOwnerName(), 
                '__defaultOwner__'
              ),
              NULL AS "foreignKey",
              datetime('subsec')
            FROM (SELECT 1) 
            LEFT JOIN "sqlitedata_icloud_metadata" ON "sqlitedata_icloud_metadata"."recordName" = "foreignKey"
            ON CONFLICT("recordName") DO NOTHING;
          END
          """,
          [16]: """
          CREATE TRIGGER "sqlitedata_icloud_users_metadataUpdates"
          AFTER UPDATE ON "users" FOR EACH ROW BEGIN
            UPDATE "sqlitedata_icloud_metadata"
            SET
              "recordName" = "new"."id",
              "userModificationDate" = datetime('subsec'),
              "parentRecordName" = NULL
            WHERE "recordName" = "old"."id";
          END
          """,
          [17]: """
          CREATE TRIGGER "sqlitedata_icloud_users_metadataDeletes"
          AFTER DELETE ON "users" FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE "recordName" = "old"."id";
          END
          """,
          [18]: """
          CREATE TRIGGER "sqlitedata_icloud_users_belongsTo_users_onDeleteSetDefault"
          AFTER DELETE ON "users"
          FOR EACH ROW BEGIN
            UPDATE "users"
            SET "parentUserID" = NULL
            WHERE "parentUserID" = "old"."id";
          END
          """,
          [19]: """
          CREATE TRIGGER "sqlitedata_icloud_users_belongsTo_users_onUpdateCascade"
          AFTER UPDATE ON "users"
          FOR EACH ROW BEGIN
            UPDATE "users"
            SET "parentUserID" = "new"."id"
            WHERE "parentUserID" = "old"."id";
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
      privateSyncEngine.assertFetchChangesScopes([.all])
      sharedSyncEngine.assertFetchChangesScopes([.all])
      let triggersAfterReSetUp = try await database.write { db in
        try #sql("SELECT sql FROM sqlite_temp_master", as: String?.self).fetchAll(db)
      }
      expectNoDifference(triggersAfterReSetUp, triggersAfterSetUp)
    }
  }
}
