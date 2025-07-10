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
      let triggersAfterSetUp = try await userDatabase.userWrite { db in
        try #sql("SELECT sql FROM sqlite_temp_master ORDER BY sql", as: String?.self).fetchAll(db)
      }
      assertInlineSnapshot(of: triggersAfterSetUp, as: .customDump) {
        #"""
        [
          [0]: """
          CREATE TRIGGER "after_delete_on_sqlitedata_icloud_metadata"
          AFTER DELETE ON "sqlitedata_icloud_metadata"
          FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsUpdatingRecord()) BEGIN
            SELECT sqlitedata_icloud_didDelete("old"."recordName", coalesce("old"."lastKnownServerRecord", (
              WITH "ancestorMetadatas" AS (
                SELECT "sqlitedata_icloud_metadata"."recordName" AS "recordName", "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."lastKnownServerRecord" AS "lastKnownServerRecord"
                FROM "sqlitedata_icloud_metadata"
                WHERE ("sqlitedata_icloud_metadata"."recordName" = "old"."recordName")
                  UNION ALL
                SELECT "sqlitedata_icloud_metadata"."recordName" AS "recordName", "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."lastKnownServerRecord" AS "lastKnownServerRecord"
                FROM "sqlitedata_icloud_metadata"
                JOIN "ancestorMetadatas" ON ("sqlitedata_icloud_metadata"."recordName" IS "ancestorMetadatas"."parentRecordName")
              )
              SELECT "ancestorMetadatas"."lastKnownServerRecord"
              FROM "ancestorMetadatas"
              WHERE ("ancestorMetadatas"."parentRecordName" IS NULL)
            )));
          END
          """,
          [1]: """
          CREATE TRIGGER "after_insert_on_sqlitedata_icloud_metadata"
          AFTER INSERT ON "sqlitedata_icloud_metadata"
          FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsUpdatingRecord()) BEGIN
            SELECT sqlitedata_icloud_didUpdate("new"."recordName", coalesce("new"."lastKnownServerRecord", (
              WITH "ancestorMetadatas" AS (
                SELECT "sqlitedata_icloud_metadata"."recordName" AS "recordName", "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."lastKnownServerRecord" AS "lastKnownServerRecord"
                FROM "sqlitedata_icloud_metadata"
                WHERE ("sqlitedata_icloud_metadata"."recordName" = "new"."recordName")
                  UNION ALL
                SELECT "sqlitedata_icloud_metadata"."recordName" AS "recordName", "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."lastKnownServerRecord" AS "lastKnownServerRecord"
                FROM "sqlitedata_icloud_metadata"
                JOIN "ancestorMetadatas" ON ("sqlitedata_icloud_metadata"."recordName" IS "ancestorMetadatas"."parentRecordName")
              )
              SELECT "ancestorMetadatas"."lastKnownServerRecord"
              FROM "ancestorMetadatas"
              WHERE ("ancestorMetadatas"."parentRecordName" IS NULL)
            )));
          END
          """,
          [2]: """
          CREATE TRIGGER "after_update_on_sqlitedata_icloud_metadata"
          AFTER UPDATE ON "sqlitedata_icloud_metadata"
          FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsUpdatingRecord()) BEGIN
            SELECT sqlitedata_icloud_didUpdate("new"."recordName", coalesce("new"."lastKnownServerRecord", (
              WITH "ancestorMetadatas" AS (
                SELECT "sqlitedata_icloud_metadata"."recordName" AS "recordName", "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."lastKnownServerRecord" AS "lastKnownServerRecord"
                FROM "sqlitedata_icloud_metadata"
                WHERE ("sqlitedata_icloud_metadata"."recordName" = "new"."recordName")
                  UNION ALL
                SELECT "sqlitedata_icloud_metadata"."recordName" AS "recordName", "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."lastKnownServerRecord" AS "lastKnownServerRecord"
                FROM "sqlitedata_icloud_metadata"
                JOIN "ancestorMetadatas" ON ("sqlitedata_icloud_metadata"."recordName" IS "ancestorMetadatas"."parentRecordName")
              )
              SELECT "ancestorMetadatas"."lastKnownServerRecord"
              FROM "ancestorMetadatas"
              WHERE ("ancestorMetadatas"."parentRecordName" IS NULL)
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
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelAs"
          AFTER DELETE ON "modelAs"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'modelAs');
          END
          """,
          [7]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelBs"
          AFTER DELETE ON "modelBs"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'modelBs');
          END
          """,
          [8]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelCs"
          AFTER DELETE ON "modelCs"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'modelCs');
          END
          """,
          [9]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_parents"
          AFTER DELETE ON "parents"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'parents');
          END
          """,
          [10]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_reminderTags"
          AFTER DELETE ON "reminderTags"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'reminderTags');
          END
          """,
          [11]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_reminders"
          AFTER DELETE ON "reminders"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'reminders');
          END
          """,
          [12]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersListAssets"
          AFTER DELETE ON "remindersListAssets"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'remindersListAssets');
          END
          """,
          [13]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersListPrivates"
          AFTER DELETE ON "remindersListPrivates"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'remindersListPrivates');
          END
          """,
          [14]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersLists"
          AFTER DELETE ON "remindersLists"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'remindersLists');
          END
          """,
          [15]: """
          CREATE TRIGGER "sqlitedata_icloud_after_delete_on_tags"
          AFTER DELETE ON "tags"
          FOR EACH ROW BEGIN
            DELETE FROM "sqlitedata_icloud_metadata"
            WHERE ("sqlitedata_icloud_metadata"."recordName" =  "old"."id" || ':' || 'tags');
          END
          """,
          [16]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_childWithOnDeleteRestricts"
          AFTER INSERT ON "childWithOnDeleteRestricts"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'childWithOnDeleteRestricts',  "new"."id" || ':' || 'childWithOnDeleteRestricts', "new"."parentID" || ':' || 'parents' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [17]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_childWithOnDeleteSetDefaults"
          AFTER INSERT ON "childWithOnDeleteSetDefaults"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'childWithOnDeleteSetDefaults',  "new"."id" || ':' || 'childWithOnDeleteSetDefaults', "new"."parentID" || ':' || 'parents' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [18]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_childWithOnDeleteSetNulls"
          AFTER INSERT ON "childWithOnDeleteSetNulls"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'childWithOnDeleteSetNulls',  "new"."id" || ':' || 'childWithOnDeleteSetNulls', "new"."parentID" || ':' || 'parents' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [19]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_modelAs"
          AFTER INSERT ON "modelAs"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'modelAs',  "new"."id" || ':' || 'modelAs', NULL AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [20]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_modelBs"
          AFTER INSERT ON "modelBs"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'modelBs',  "new"."id" || ':' || 'modelBs', "new"."modelAID" || ':' || 'modelAs' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [21]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_modelCs"
          AFTER INSERT ON "modelCs"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'modelCs',  "new"."id" || ':' || 'modelCs', "new"."modelBID" || ':' || 'modelBs' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [22]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_parents"
          AFTER INSERT ON "parents"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'parents',  "new"."id" || ':' || 'parents', NULL AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [23]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_reminderTags"
          AFTER INSERT ON "reminderTags"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'reminderTags',  "new"."id" || ':' || 'reminderTags', NULL AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [24]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_reminders"
          AFTER INSERT ON "reminders"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'reminders',  "new"."id" || ':' || 'reminders', "new"."remindersListID" || ':' || 'remindersLists' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [25]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_remindersListAssets"
          AFTER INSERT ON "remindersListAssets"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'remindersListAssets',  "new"."id" || ':' || 'remindersListAssets', "new"."remindersListID" || ':' || 'remindersLists' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [26]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_remindersListPrivates"
          AFTER INSERT ON "remindersListPrivates"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'remindersListPrivates',  "new"."id" || ':' || 'remindersListPrivates', "new"."remindersListID" || ':' || 'remindersLists' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [27]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_remindersLists"
          AFTER INSERT ON "remindersLists"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'remindersLists',  "new"."id" || ':' || 'remindersLists', NULL AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [28]: """
          CREATE TRIGGER "sqlitedata_icloud_after_insert_on_tags"
          AFTER INSERT ON "tags"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'tags',  "new"."id" || ':' || 'tags', NULL AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [29]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_childWithOnDeleteRestricts"
          AFTER UPDATE ON "childWithOnDeleteRestricts"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'childWithOnDeleteRestricts',  "new"."id" || ':' || 'childWithOnDeleteRestricts', "new"."parentID" || ':' || 'parents' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [30]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_childWithOnDeleteSetDefaults"
          AFTER UPDATE ON "childWithOnDeleteSetDefaults"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'childWithOnDeleteSetDefaults',  "new"."id" || ':' || 'childWithOnDeleteSetDefaults', "new"."parentID" || ':' || 'parents' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [31]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_childWithOnDeleteSetNulls"
          AFTER UPDATE ON "childWithOnDeleteSetNulls"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'childWithOnDeleteSetNulls',  "new"."id" || ':' || 'childWithOnDeleteSetNulls', "new"."parentID" || ':' || 'parents' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [32]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_modelAs"
          AFTER UPDATE ON "modelAs"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'modelAs',  "new"."id" || ':' || 'modelAs', NULL AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [33]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_modelBs"
          AFTER UPDATE ON "modelBs"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'modelBs',  "new"."id" || ':' || 'modelBs', "new"."modelAID" || ':' || 'modelAs' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [34]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_modelCs"
          AFTER UPDATE ON "modelCs"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'modelCs',  "new"."id" || ':' || 'modelCs', "new"."modelBID" || ':' || 'modelBs' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [35]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_parents"
          AFTER UPDATE ON "parents"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'parents',  "new"."id" || ':' || 'parents', NULL AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [36]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_reminderTags"
          AFTER UPDATE ON "reminderTags"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'reminderTags',  "new"."id" || ':' || 'reminderTags', NULL AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [37]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_reminders"
          AFTER UPDATE ON "reminders"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'reminders',  "new"."id" || ':' || 'reminders', "new"."remindersListID" || ':' || 'remindersLists' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [38]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_remindersListAssets"
          AFTER UPDATE ON "remindersListAssets"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'remindersListAssets',  "new"."id" || ':' || 'remindersListAssets', "new"."remindersListID" || ':' || 'remindersLists' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [39]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_remindersListPrivates"
          AFTER UPDATE ON "remindersListPrivates"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'remindersListPrivates',  "new"."id" || ':' || 'remindersListPrivates', "new"."remindersListID" || ':' || 'remindersLists' AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [40]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_remindersLists"
          AFTER UPDATE ON "remindersLists"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'remindersLists',  "new"."id" || ':' || 'remindersLists', NULL AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [41]: """
          CREATE TRIGGER "sqlitedata_icloud_after_update_on_tags"
          AFTER UPDATE ON "tags"
          FOR EACH ROW BEGIN
            INSERT INTO "sqlitedata_icloud_metadata"
            ("recordType", "recordName", "parentRecordName")
            SELECT 'tags',  "new"."id" || ':' || 'tags', NULL AS "foreignKey"
            ON CONFLICT ("recordName")
            DO UPDATE SET "recordName" = "excluded"."recordName", "parentRecordName" = "excluded"."parentRecordName", "userModificationDate" = "excluded"."userModificationDate";
          END
          """,
          [42]: """
          CREATE TRIGGER "sqlitedata_icloud_childWithOnDeleteRestricts_belongsTo_parents_onDeleteRestrict"
          BEFORE DELETE ON "parents"
          FOR EACH ROW BEGIN
            SELECT RAISE(ABORT, 'FOREIGN KEY constraint failed')
            FROM "childWithOnDeleteRestricts"
            WHERE "parentID" = "old"."id";
          END
          """,
          [43]: """
          CREATE TRIGGER "sqlitedata_icloud_childWithOnDeleteRestricts_belongsTo_parents_onUpdateRestrict"
          BEFORE UPDATE ON "parents"
          FOR EACH ROW BEGIN
            SELECT RAISE(ABORT, 'FOREIGN KEY constraint failed')
            FROM "childWithOnDeleteRestricts"
            WHERE "parentID" = "old"."id";
          END
          """,
          [44]: """
          CREATE TRIGGER "sqlitedata_icloud_childWithOnDeleteSetDefaults_belongsTo_parents_onDeleteSetDefault"
          AFTER DELETE ON "parents"
          FOR EACH ROW BEGIN
            UPDATE "childWithOnDeleteSetDefaults"
            SET "parentID" = NULL
            WHERE "parentID" = "old"."id";
          END
          """,
          [45]: """
          CREATE TRIGGER "sqlitedata_icloud_childWithOnDeleteSetDefaults_belongsTo_parents_onUpdateSetDefault"
          AFTER UPDATE ON "parents"
          FOR EACH ROW BEGIN
            UPDATE "childWithOnDeleteSetDefaults"
            SET "parentID" = NULL
            WHERE "parentID" = "old"."id";
          END
          """,
          [46]: """
          CREATE TRIGGER "sqlitedata_icloud_childWithOnDeleteSetNulls_belongsTo_parents_onDeleteSetNull"
          AFTER DELETE ON "parents"
          FOR EACH ROW BEGIN
            UPDATE "childWithOnDeleteSetNulls"
            SET "parentID" = NULL
            WHERE "parentID" = "old"."id";
          END
          """,
          [47]: """
          CREATE TRIGGER "sqlitedata_icloud_childWithOnDeleteSetNulls_belongsTo_parents_onUpdateSetNull"
          AFTER UPDATE ON "parents"
          FOR EACH ROW BEGIN
            UPDATE "childWithOnDeleteSetNulls"
            SET "parentID" = NULL
            WHERE "parentID" = "old"."id";
          END
          """,
          [48]: """
          CREATE TRIGGER "sqlitedata_icloud_localUsers_belongsTo_localUsers_onDeleteCascade"
          AFTER DELETE ON "localUsers"
          FOR EACH ROW BEGIN
            DELETE FROM "localUsers"
            WHERE "parentID" = "old"."id";
          END
          """,
          [49]: """
          CREATE TRIGGER "sqlitedata_icloud_modelBs_belongsTo_modelAs_onDeleteCascade"
          AFTER DELETE ON "modelAs"
          FOR EACH ROW BEGIN
            DELETE FROM "modelBs"
            WHERE "modelAID" = "old"."id";
          END
          """,
          [50]: """
          CREATE TRIGGER "sqlitedata_icloud_modelCs_belongsTo_modelBs_onDeleteCascade"
          AFTER DELETE ON "modelBs"
          FOR EACH ROW BEGIN
            DELETE FROM "modelCs"
            WHERE "modelBID" = "old"."id";
          END
          """,
          [51]: """
          CREATE TRIGGER "sqlitedata_icloud_reminderTags_belongsTo_reminders_onDeleteCascade"
          AFTER DELETE ON "reminders"
          FOR EACH ROW BEGIN
            DELETE FROM "reminderTags"
            WHERE "reminderID" = "old"."id";
          END
          """,
          [52]: """
          CREATE TRIGGER "sqlitedata_icloud_reminderTags_belongsTo_tags_onDeleteCascade"
          AFTER DELETE ON "tags"
          FOR EACH ROW BEGIN
            DELETE FROM "reminderTags"
            WHERE "tagID" = "old"."id";
          END
          """,
          [53]: """
          CREATE TRIGGER "sqlitedata_icloud_remindersListAssets_belongsTo_remindersLists_onDeleteCascade"
          AFTER DELETE ON "remindersLists"
          FOR EACH ROW BEGIN
            DELETE FROM "remindersListAssets"
            WHERE "remindersListID" = "old"."id";
          END
          """,
          [54]: """
          CREATE TRIGGER "sqlitedata_icloud_remindersListPrivates_belongsTo_remindersLists_onDeleteCascade"
          AFTER DELETE ON "remindersLists"
          FOR EACH ROW BEGIN
            DELETE FROM "remindersListPrivates"
            WHERE "remindersListID" = "old"."id";
          END
          """,
          [55]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_belongsTo_remindersLists_onDeleteCascade"
          AFTER DELETE ON "remindersLists"
          FOR EACH ROW BEGIN
            DELETE FROM "reminders"
            WHERE "remindersListID" = "old"."id";
          END
          """,
          [56]: """
          CREATE TRIGGER "sqlitedata_icloud_reminders_belongsTo_remindersLists_onUpdateCascade"
          AFTER UPDATE ON "remindersLists"
          FOR EACH ROW BEGIN
            UPDATE "reminders"
            SET "remindersListID" = "new"."id"
            WHERE "remindersListID" = "old"."id";
          END
          """
        ]
        """#
      }

      try await syncEngine.tearDownSyncEngine()
      let triggersAfterTearDown = try await userDatabase.userWrite { db in
        try #sql("SELECT sql FROM sqlite_temp_master", as: String?.self).fetchAll(db)
      }
      assertInlineSnapshot(of: triggersAfterTearDown, as: .customDump) {
        """
        []
        """
      }

      try await syncEngine.setUpSyncEngine()
      let triggersAfterReSetUp = try await userDatabase.userWrite { db in
        try #sql("SELECT sql FROM sqlite_temp_master ORDER BY sql", as: String?.self).fetchAll(db)
      }
      expectNoDifference(triggersAfterReSetUp, triggersAfterSetUp)
    }
  }
}
