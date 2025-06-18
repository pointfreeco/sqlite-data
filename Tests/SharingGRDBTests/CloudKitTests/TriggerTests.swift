import CloudKit
import CustomDump
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
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
          CREATE TRIGGER "after_insert_on_sqlitedata_icloud_metadata@SharingGRDBCore/Metadata.swift:6:69"
          AFTER INSERT ON "sqlitedata_icloud_metadata"
          FOR EACH ROW WHEN NOT sqlitedata_icloud_isUpdatingWithServerRecord() BEGIN
            SELECT sqlitedata_icloud_didUpdate("new"."recordName");
          END
          """,
          [1]: """
          CREATE TRIGGER "after_update_on_sqlitedata_icloud_metadata@SharingGRDBCore/Metadata.swift:17:69"
          AFTER UPDATE ON "sqlitedata_icloud_metadata"
          FOR EACH ROW WHEN NOT sqlitedata_icloud_isUpdatingWithServerRecord() BEGIN
            SELECT sqlitedata_icloud_didUpdate("new"."recordName");
          END
          """,
          [2]: """
          CREATE TRIGGER "after_delete_on_sqlitedata_icloud_metadata@SharingGRDBCore/Metadata.swift:28:69"
          AFTER DELETE ON "sqlitedata_icloud_metadata"
          FOR EACH ROW WHEN NOT sqlitedata_icloud_isUpdatingWithServerRecord() BEGIN
            SELECT sqlitedata_icloud_didDelete("old"."recordName");
          END
          """,
          [3]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_metadataInserts"
          AFTER INSERT ON "reminders" FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            (
              "recordType",
              "recordName",
              "parentRecordName",
              "userModificationDate"
            )
          SELECT
            'reminders',
            "new"."id",
            "new"."remindersListID" AS "foreignKey",
            datetime('subsec')
          ON CONFLICT("recordName") DO UPDATE
          SET
            "recordType" = "excluded"."recordType",
            "parentRecordName" = "excluded"."parentRecordName",
            "userModificationDate"  = "excluded"."userModificationDate";
          END
          """,
          [4]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_metadataUpdates"
          AFTER UPDATE ON "reminders" FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            (
              "recordType",
              "recordName",
              "parentRecordName",
              "userModificationDate"
            )
          SELECT
            'reminders',
            "new"."id",
            "new"."remindersListID" AS "foreignKey",
            datetime('subsec')
          ON CONFLICT("recordName") DO UPDATE
          SET
            "recordType" = "excluded"."recordType",
            "parentRecordName" = "excluded"."parentRecordName",
            "userModificationDate"  = "excluded"."userModificationDate";
          END
          """,
          [5]: """
          CREATE TRIGGER "after_delete_on_reminders@SharingGRDBCore/Metadata.swift:145:27"
          AFTER DELETE ON "reminders"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" = "old"."id");
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
              "parentRecordName",
              "userModificationDate"
            )
          SELECT
            'remindersLists',
            "new"."id",
            NULL AS "foreignKey",
            datetime('subsec')
          ON CONFLICT("recordName") DO UPDATE
          SET
            "recordType" = "excluded"."recordType",
            "parentRecordName" = "excluded"."parentRecordName",
            "userModificationDate"  = "excluded"."userModificationDate";
          END
          """,
          [13]: """
          CREATE TRIGGER "sqlitedata_icloud_remindersLists_metadataUpdates"
          AFTER UPDATE ON "remindersLists" FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            (
              "recordType",
              "recordName",
              "parentRecordName",
              "userModificationDate"
            )
          SELECT
            'remindersLists',
            "new"."id",
            NULL AS "foreignKey",
            datetime('subsec')
          ON CONFLICT("recordName") DO UPDATE
          SET
            "recordType" = "excluded"."recordType",
            "parentRecordName" = "excluded"."parentRecordName",
            "userModificationDate"  = "excluded"."userModificationDate";
          END
          """,
          [14]: """
          CREATE TRIGGER "after_delete_on_remindersLists@SharingGRDBCore/Metadata.swift:145:27"
          AFTER DELETE ON "remindersLists"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" = "old"."id");
          END
          """,
          [15]: """
          CREATE TRIGGER "sqlitedata_icloud_users_metadataInserts"
          AFTER INSERT ON "users" FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            (
              "recordType",
              "recordName",
              "parentRecordName",
              "userModificationDate"
            )
          SELECT
            'users',
            "new"."id",
            NULL AS "foreignKey",
            datetime('subsec')
          ON CONFLICT("recordName") DO UPDATE
          SET
            "recordType" = "excluded"."recordType",
            "parentRecordName" = "excluded"."parentRecordName",
            "userModificationDate"  = "excluded"."userModificationDate";
          END
          """,
          [16]: """
          CREATE TRIGGER "sqlitedata_icloud_users_metadataUpdates"
          AFTER UPDATE ON "users" FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            (
              "recordType",
              "recordName",
              "parentRecordName",
              "userModificationDate"
            )
          SELECT
            'users',
            "new"."id",
            NULL AS "foreignKey",
            datetime('subsec')
          ON CONFLICT("recordName") DO UPDATE
          SET
            "recordType" = "excluded"."recordType",
            "parentRecordName" = "excluded"."parentRecordName",
            "userModificationDate"  = "excluded"."userModificationDate";
          END
          """,
          [17]: """
          CREATE TRIGGER "after_delete_on_users@SharingGRDBCore/Metadata.swift:145:27"
          AFTER DELETE ON "users"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" = "old"."id");
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
