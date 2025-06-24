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
        try #sql("SELECT sql FROM sqlite_temp_master ORDER BY sql", as: String?.self).fetchAll(db)
      }
      assertInlineSnapshot(of: triggersAfterSetUp, as: .customDump) {
        #"""
        [
          [0]: """
          CREATE TRIGGER "after_delete_on_sqlitedata_icloud_metadata"
          AFTER DELETE ON "sqlitedata_icloud_metadata"
          FOR EACH ROW WHEN NOT (sqlitedata_icloud_isUpdatingWithServerRecord()) BEGIN
            SELECT sqlitedata_icloud_didDelete("old"."recordName", coalesce("old"."lastKnownServerRecord", (
              SELECT "sqlitedata_icloud_metadata"."lastKnownServerRecord"
              FROM "sqlitedata_icloud_metadata"
              WHERE ("sqlitedata_icloud_metadata"."recordName" IS "old"."parentRecordName")
            )));
          END
          """,
          [1]: """
          CREATE TRIGGER "after_insert_on_sqlitedata_icloud_metadata"
          AFTER INSERT ON "sqlitedata_icloud_metadata"
          FOR EACH ROW WHEN NOT (sqlitedata_icloud_isUpdatingWithServerRecord()) BEGIN
            SELECT sqlitedata_icloud_didUpdate("new"."recordName", coalesce("new"."lastKnownServerRecord", (
              SELECT "sqlitedata_icloud_metadata"."lastKnownServerRecord"
              FROM "sqlitedata_icloud_metadata"
              WHERE ("sqlitedata_icloud_metadata"."recordName" IS "new"."parentRecordName")
            )));
          END
          """,
          [2]: """
          CREATE TRIGGER "after_update_on_sqlitedata_icloud_metadata"
          AFTER UPDATE ON "sqlitedata_icloud_metadata"
          FOR EACH ROW WHEN NOT (sqlitedata_icloud_isUpdatingWithServerRecord()) BEGIN
            SELECT sqlitedata_icloud_didUpdate("new"."recordName", coalesce("new"."lastKnownServerRecord", (
              SELECT "sqlitedata_icloud_metadata"."lastKnownServerRecord"
              FROM "sqlitedata_icloud_metadata"
              WHERE ("sqlitedata_icloud_metadata"."recordName" IS "new"."parentRecordName")
            )));
          END
          """,
          [3]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_childWithOnDeleteRestricts"
          AFTER DELETE ON "childWithOnDeleteRestricts"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'childWithOnDeleteRestricts');
          END
          """,
          [4]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_childWithOnDeleteSetDefaults"
          AFTER DELETE ON "childWithOnDeleteSetDefaults"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'childWithOnDeleteSetDefaults');
          END
          """,
          [5]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_childWithOnDeleteSetNulls"
          AFTER DELETE ON "childWithOnDeleteSetNulls"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'childWithOnDeleteSetNulls');
          END
          """,
          [6]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_parents"
          AFTER DELETE ON "parents"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'parents');
          END
          """,
          [7]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_reminderTags"
          AFTER DELETE ON "reminderTags"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'reminderTags');
          END
          """,
          [8]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_reminders"
          AFTER DELETE ON "reminders"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'reminders');
          END
          """,
          [9]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersListPrivates"
          AFTER DELETE ON "remindersListPrivates"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'remindersListPrivates');
          END
          """,
          [10]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersLists"
          AFTER DELETE ON "remindersLists"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'remindersLists');
          END
          """,
          [11]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_tags"
          AFTER DELETE ON "tags"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'tags');
          END
          """,
          [12]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_users"
          AFTER DELETE ON "users"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'users');
          END
          """,
          [13]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_childWithOnDeleteRestricts"
          AFTER INSERT ON "childWithOnDeleteRestricts"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'childWithOnDeleteRestricts',  "new"."id" || ':' || 'childWithOnDeleteRestricts', "new"."parentID" || ':' || 'parents' AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [14]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_childWithOnDeleteSetDefaults"
          AFTER INSERT ON "childWithOnDeleteSetDefaults"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'childWithOnDeleteSetDefaults',  "new"."id" || ':' || 'childWithOnDeleteSetDefaults', "new"."parentID" || ':' || 'parents' AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [15]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_childWithOnDeleteSetNulls"
          AFTER INSERT ON "childWithOnDeleteSetNulls"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'childWithOnDeleteSetNulls',  "new"."id" || ':' || 'childWithOnDeleteSetNulls', "new"."parentID" || ':' || 'parents' AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [16]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_parents"
          AFTER INSERT ON "parents"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'parents',  "new"."id" || ':' || 'parents', NULL AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [17]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_reminderTags"
          AFTER INSERT ON "reminderTags"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'reminderTags',  "new"."id" || ':' || 'reminderTags', NULL AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [18]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_reminders"
          AFTER INSERT ON "reminders"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'reminders',  "new"."id" || ':' || 'reminders', "new"."remindersListID" || ':' || 'remindersLists' AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [19]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_remindersListPrivates"
          AFTER INSERT ON "remindersListPrivates"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'remindersListPrivates',  "new"."id" || ':' || 'remindersListPrivates', NULL AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [20]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_remindersLists"
          AFTER INSERT ON "remindersLists"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'remindersLists',  "new"."id" || ':' || 'remindersLists', NULL AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [21]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_tags"
          AFTER INSERT ON "tags"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'tags',  "new"."id" || ':' || 'tags', NULL AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [22]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_users"
          AFTER INSERT ON "users"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'users',  "new"."id" || ':' || 'users', "new"."parentUserID" || ':' || 'users' AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [23]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_childWithOnDeleteRestricts"
          AFTER UPDATE ON "childWithOnDeleteRestricts"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'childWithOnDeleteRestricts',  "new"."id" || ':' || 'childWithOnDeleteRestricts', "new"."parentID" || ':' || 'parents' AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [24]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_childWithOnDeleteSetDefaults"
          AFTER UPDATE ON "childWithOnDeleteSetDefaults"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'childWithOnDeleteSetDefaults',  "new"."id" || ':' || 'childWithOnDeleteSetDefaults', "new"."parentID" || ':' || 'parents' AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [25]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_childWithOnDeleteSetNulls"
          AFTER UPDATE ON "childWithOnDeleteSetNulls"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'childWithOnDeleteSetNulls',  "new"."id" || ':' || 'childWithOnDeleteSetNulls', "new"."parentID" || ':' || 'parents' AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [26]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_parents"
          AFTER UPDATE ON "parents"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'parents',  "new"."id" || ':' || 'parents', NULL AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [27]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_reminderTags"
          AFTER UPDATE ON "reminderTags"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'reminderTags',  "new"."id" || ':' || 'reminderTags', NULL AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [28]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_reminders"
          AFTER UPDATE ON "reminders"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'reminders',  "new"."id" || ':' || 'reminders', "new"."remindersListID" || ':' || 'remindersLists' AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [29]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_remindersListPrivates"
          AFTER UPDATE ON "remindersListPrivates"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'remindersListPrivates',  "new"."id" || ':' || 'remindersListPrivates', NULL AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [30]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_remindersLists"
          AFTER UPDATE ON "remindersLists"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'remindersLists',  "new"."id" || ':' || 'remindersLists', NULL AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [31]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_tags"
          AFTER UPDATE ON "tags"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'tags',  "new"."id" || ':' || 'tags', NULL AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [32]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_users"
          AFTER UPDATE ON "users"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName", "userModificationDate")
            SELECT 'users',  "new"."id" || ':' || 'users', "new"."parentUserID" || ':' || 'users' AS "foreignKey", sqlitedata_icloud_datetime()
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [33]: """
          CREATE TRIGGER "sqlitedata_icloud_childWithOnDeleteRestricts_belongsTo_parents_onDeleteRestrict"
          BEFORE DELETE ON "parents"
          FOR EACH ROW BEGIN
            SELECT RAISE(ABORT, 'FOREIGN KEY constraint failed')
            FROM "childWithOnDeleteRestricts"
            WHERE "parentID" = "old"."id";
          END
          """,
          [34]: """
          CREATE TRIGGER "sqlitedata_icloud_childWithOnDeleteRestricts_belongsTo_parents_onUpdateRestrict"
          BEFORE UPDATE ON "parents"
          FOR EACH ROW BEGIN
            SELECT RAISE(ABORT, 'FOREIGN KEY constraint failed')
            FROM "childWithOnDeleteRestricts"
            WHERE "parentID" = "old"."id";
          END
          """,
          [35]: """
          CREATE TRIGGER "sqlitedata_icloud_childWithOnDeleteSetDefaults_belongsTo_parents_onDeleteSetDefault"
          AFTER DELETE ON "parents"
          FOR EACH ROW BEGIN
            UPDATE "childWithOnDeleteSetDefaults"
            SET "parentID" = NULL
            WHERE "parentID" = "old"."id";
          END
          """,
          [36]: """
          CREATE TRIGGER "sqlitedata_icloud_childWithOnDeleteSetDefaults_belongsTo_parents_onUpdateSetDefault"
          AFTER UPDATE ON "parents"
          FOR EACH ROW BEGIN
            UPDATE "childWithOnDeleteSetDefaults"
            SET "parentID" = NULL
            WHERE "parentID" = "old"."id";
          END
          """,
          [37]: """
          CREATE TRIGGER "sqlitedata_icloud_childWithOnDeleteSetNulls_belongsTo_parents_onDeleteSetNull"
          AFTER DELETE ON "parents"
          FOR EACH ROW BEGIN
            UPDATE "childWithOnDeleteSetNulls"
            SET "parentID" = NULL
            WHERE "parentID" = "old"."id";
          END
          """,
          [38]: """
          CREATE TRIGGER "sqlitedata_icloud_childWithOnDeleteSetNulls_belongsTo_parents_onUpdateSetNull"
          AFTER UPDATE ON "parents"
          FOR EACH ROW BEGIN
            UPDATE "childWithOnDeleteSetNulls"
            SET "parentID" = NULL
            WHERE "parentID" = "old"."id";
          END
          """,
          [39]: """
          CREATE TRIGGER "sqlitedata_icloud_reminderTags_belongsTo_reminders_onDeleteCascade"
          AFTER DELETE ON "reminders"
          FOR EACH ROW BEGIN
            DELETE FROM "reminderTags"
            WHERE "reminderID" = "old"."id";
          END
          """,
          [40]: """
          CREATE TRIGGER "sqlitedata_icloud_reminderTags_belongsTo_tags_onDeleteCascade"
          AFTER DELETE ON "tags"
          FOR EACH ROW BEGIN
            DELETE FROM "reminderTags"
            WHERE "tagID" = "old"."id";
          END
          """,
          [41]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_belongsTo_remindersLists_onDeleteCascade"
          AFTER DELETE ON "remindersLists"
          FOR EACH ROW BEGIN
            DELETE FROM "reminders"
            WHERE "remindersListID" = "old"."id";
          END
          """,
          [42]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_belongsTo_remindersLists_onUpdateCascade"
          AFTER UPDATE ON "remindersLists"
          FOR EACH ROW BEGIN
            UPDATE "reminders"
            SET "remindersListID" = "new"."id"
            WHERE "remindersListID" = "old"."id";
          END
          """,
          [43]: """
          CREATE TRIGGER "sqlitedata_icloud_users_belongsTo_users_onDeleteSetDefault"
          AFTER DELETE ON "users"
          FOR EACH ROW BEGIN
            UPDATE "users"
            SET "parentUserID" = NULL
            WHERE "parentUserID" = "old"."id";
          END
          """,
          [44]: """
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
        try #sql("SELECT sql FROM sqlite_temp_master ORDER BY sql", as: String?.self).fetchAll(db)
      }
      expectNoDifference(triggersAfterReSetUp, triggersAfterSetUp)
    }
  }
}
