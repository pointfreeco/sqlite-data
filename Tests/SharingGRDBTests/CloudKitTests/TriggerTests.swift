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
      #if DEBUG
        assertInlineSnapshot(of: triggersAfterSetUp, as: .customDump) {
          #"""
          [
            [0]: """
            CREATE TRIGGER "after_delete_on_sqlitedata_icloud_metadata"
            AFTER UPDATE OF "isDeleted" ON "sqlitedata_icloud_metadata"
            FOR EACH ROW WHEN (NOT ("old"."isDeleted") AND "new"."isDeleted") BEGIN
              SELECT sqlitedata_icloud_didDelete("new"."recordName", coalesce("new"."lastKnownServerRecord", (
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
              )), "new"."share");
            END
            """,
            [1]: """
            CREATE TRIGGER "after_insert_on_sqlitedata_icloud_metadata"
            AFTER INSERT ON "sqlitedata_icloud_metadata"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
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
              )), "new"."share");
            END
            """,
            [2]: """
            CREATE TRIGGER "after_update_on_sqlitedata_icloud_metadata"
            AFTER UPDATE ON "sqlitedata_icloud_metadata"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
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
              )), "new"."share");
            END
            """,
            [3]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_childWithOnDeleteSetDefaults_from_sync_engine"
            AFTER DELETE ON "childWithOnDeleteSetDefaults"
            FOR EACH ROW WHEN sqlitedata_icloud_syncEngineIsSynchronizingChanges() BEGIN
              DELETE FROM "sqlitedata_icloud_metadata"
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'childWithOnDeleteSetDefaults'));
            END
            """,
            [4]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_childWithOnDeleteSetDefaults_from_user"
            AFTER DELETE ON "childWithOnDeleteSetDefaults"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
              UPDATE "sqlitedata_icloud_metadata"
              SET "isDeleted" = 1
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'childWithOnDeleteSetDefaults'));
            END
            """,
            [5]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_childWithOnDeleteSetNulls_from_sync_engine"
            AFTER DELETE ON "childWithOnDeleteSetNulls"
            FOR EACH ROW WHEN sqlitedata_icloud_syncEngineIsSynchronizingChanges() BEGIN
              DELETE FROM "sqlitedata_icloud_metadata"
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'childWithOnDeleteSetNulls'));
            END
            """,
            [6]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_childWithOnDeleteSetNulls_from_user"
            AFTER DELETE ON "childWithOnDeleteSetNulls"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
              UPDATE "sqlitedata_icloud_metadata"
              SET "isDeleted" = 1
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'childWithOnDeleteSetNulls'));
            END
            """,
            [7]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelAs_from_sync_engine"
            AFTER DELETE ON "modelAs"
            FOR EACH ROW WHEN sqlitedata_icloud_syncEngineIsSynchronizingChanges() BEGIN
              DELETE FROM "sqlitedata_icloud_metadata"
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'modelAs'));
            END
            """,
            [8]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelAs_from_user"
            AFTER DELETE ON "modelAs"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
              UPDATE "sqlitedata_icloud_metadata"
              SET "isDeleted" = 1
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'modelAs'));
            END
            """,
            [9]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelBs_from_sync_engine"
            AFTER DELETE ON "modelBs"
            FOR EACH ROW WHEN sqlitedata_icloud_syncEngineIsSynchronizingChanges() BEGIN
              DELETE FROM "sqlitedata_icloud_metadata"
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'modelBs'));
            END
            """,
            [10]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelBs_from_user"
            AFTER DELETE ON "modelBs"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
              UPDATE "sqlitedata_icloud_metadata"
              SET "isDeleted" = 1
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'modelBs'));
            END
            """,
            [11]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelCs_from_sync_engine"
            AFTER DELETE ON "modelCs"
            FOR EACH ROW WHEN sqlitedata_icloud_syncEngineIsSynchronizingChanges() BEGIN
              DELETE FROM "sqlitedata_icloud_metadata"
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'modelCs'));
            END
            """,
            [12]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelCs_from_user"
            AFTER DELETE ON "modelCs"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
              UPDATE "sqlitedata_icloud_metadata"
              SET "isDeleted" = 1
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'modelCs'));
            END
            """,
            [13]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_parents_from_sync_engine"
            AFTER DELETE ON "parents"
            FOR EACH ROW WHEN sqlitedata_icloud_syncEngineIsSynchronizingChanges() BEGIN
              DELETE FROM "sqlitedata_icloud_metadata"
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'parents'));
            END
            """,
            [14]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_parents_from_user"
            AFTER DELETE ON "parents"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
              UPDATE "sqlitedata_icloud_metadata"
              SET "isDeleted" = 1
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'parents'));
            END
            """,
            [15]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_reminderTags_from_sync_engine"
            AFTER DELETE ON "reminderTags"
            FOR EACH ROW WHEN sqlitedata_icloud_syncEngineIsSynchronizingChanges() BEGIN
              DELETE FROM "sqlitedata_icloud_metadata"
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'reminderTags'));
            END
            """,
            [16]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_reminderTags_from_user"
            AFTER DELETE ON "reminderTags"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
              UPDATE "sqlitedata_icloud_metadata"
              SET "isDeleted" = 1
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'reminderTags'));
            END
            """,
            [17]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersListAssets_from_sync_engine"
            AFTER DELETE ON "remindersListAssets"
            FOR EACH ROW WHEN sqlitedata_icloud_syncEngineIsSynchronizingChanges() BEGIN
              DELETE FROM "sqlitedata_icloud_metadata"
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'remindersListAssets'));
            END
            """,
            [18]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersListAssets_from_user"
            AFTER DELETE ON "remindersListAssets"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
              UPDATE "sqlitedata_icloud_metadata"
              SET "isDeleted" = 1
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'remindersListAssets'));
            END
            """,
            [19]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersListPrivates_from_sync_engine"
            AFTER DELETE ON "remindersListPrivates"
            FOR EACH ROW WHEN sqlitedata_icloud_syncEngineIsSynchronizingChanges() BEGIN
              DELETE FROM "sqlitedata_icloud_metadata"
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'remindersListPrivates'));
            END
            """,
            [20]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersListPrivates_from_user"
            AFTER DELETE ON "remindersListPrivates"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
              UPDATE "sqlitedata_icloud_metadata"
              SET "isDeleted" = 1
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'remindersListPrivates'));
            END
            """,
            [21]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersLists_from_sync_engine"
            AFTER DELETE ON "remindersLists"
            FOR EACH ROW WHEN sqlitedata_icloud_syncEngineIsSynchronizingChanges() BEGIN
              DELETE FROM "sqlitedata_icloud_metadata"
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'remindersLists'));
            END
            """,
            [22]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersLists_from_user"
            AFTER DELETE ON "remindersLists"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
              UPDATE "sqlitedata_icloud_metadata"
              SET "isDeleted" = 1
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'remindersLists'));
            END
            """,
            [23]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_reminders_from_sync_engine"
            AFTER DELETE ON "reminders"
            FOR EACH ROW WHEN sqlitedata_icloud_syncEngineIsSynchronizingChanges() BEGIN
              DELETE FROM "sqlitedata_icloud_metadata"
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'reminders'));
            END
            """,
            [24]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_reminders_from_user"
            AFTER DELETE ON "reminders"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
              UPDATE "sqlitedata_icloud_metadata"
              SET "isDeleted" = 1
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."id") AND ("sqlitedata_icloud_metadata"."recordType" = 'reminders'));
            END
            """,
            [25]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_tags_from_sync_engine"
            AFTER DELETE ON "tags"
            FOR EACH ROW WHEN sqlitedata_icloud_syncEngineIsSynchronizingChanges() BEGIN
              DELETE FROM "sqlitedata_icloud_metadata"
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."title") AND ("sqlitedata_icloud_metadata"."recordType" = 'tags'));
            END
            """,
            [26]: """
            CREATE TRIGGER "sqlitedata_icloud_after_delete_on_tags_from_user"
            AFTER DELETE ON "tags"
            FOR EACH ROW WHEN NOT (sqlitedata_icloud_syncEngineIsSynchronizingChanges()) BEGIN
              UPDATE "sqlitedata_icloud_metadata"
              SET "isDeleted" = 1
              WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey" = "old"."title") AND ("sqlitedata_icloud_metadata"."recordType" = 'tags'));
            END
            """,
            [27]: """
            CREATE TRIGGER "sqlitedata_icloud_after_insert_on_childWithOnDeleteSetDefaults"
            AFTER INSERT ON "childWithOnDeleteSetDefaults"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'childWithOnDeleteSetDefaults', "new"."parentID", 'parents'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [28]: """
            CREATE TRIGGER "sqlitedata_icloud_after_insert_on_childWithOnDeleteSetNulls"
            AFTER INSERT ON "childWithOnDeleteSetNulls"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'childWithOnDeleteSetNulls', "new"."parentID", 'parents'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [29]: """
            CREATE TRIGGER "sqlitedata_icloud_after_insert_on_modelAs"
            AFTER INSERT ON "modelAs"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'modelAs', NULL, NULL
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [30]: """
            CREATE TRIGGER "sqlitedata_icloud_after_insert_on_modelBs"
            AFTER INSERT ON "modelBs"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'modelBs', "new"."modelAID", 'modelAs'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [31]: """
            CREATE TRIGGER "sqlitedata_icloud_after_insert_on_modelCs"
            AFTER INSERT ON "modelCs"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'modelCs', "new"."modelBID", 'modelBs'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [32]: """
            CREATE TRIGGER "sqlitedata_icloud_after_insert_on_parents"
            AFTER INSERT ON "parents"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'parents', NULL, NULL
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [33]: """
            CREATE TRIGGER "sqlitedata_icloud_after_insert_on_reminderTags"
            AFTER INSERT ON "reminderTags"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'reminderTags', NULL, NULL
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [34]: """
            CREATE TRIGGER "sqlitedata_icloud_after_insert_on_reminders"
            AFTER INSERT ON "reminders"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'reminders', "new"."remindersListID", 'remindersLists'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [35]: """
            CREATE TRIGGER "sqlitedata_icloud_after_insert_on_remindersListAssets"
            AFTER INSERT ON "remindersListAssets"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'remindersListAssets', "new"."remindersListID", 'remindersLists'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [36]: """
            CREATE TRIGGER "sqlitedata_icloud_after_insert_on_remindersListPrivates"
            AFTER INSERT ON "remindersListPrivates"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'remindersListPrivates', "new"."remindersListID", 'remindersLists'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [37]: """
            CREATE TRIGGER "sqlitedata_icloud_after_insert_on_remindersLists"
            AFTER INSERT ON "remindersLists"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'remindersLists', NULL, NULL
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [38]: """
            CREATE TRIGGER "sqlitedata_icloud_after_insert_on_tags"
            AFTER INSERT ON "tags"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."title", 'tags', NULL, NULL
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [39]: """
            CREATE TRIGGER "sqlitedata_icloud_after_update_on_childWithOnDeleteSetDefaults"
            AFTER UPDATE ON "childWithOnDeleteSetDefaults"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'childWithOnDeleteSetDefaults', "new"."parentID", 'parents'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [40]: """
            CREATE TRIGGER "sqlitedata_icloud_after_update_on_childWithOnDeleteSetNulls"
            AFTER UPDATE ON "childWithOnDeleteSetNulls"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'childWithOnDeleteSetNulls', "new"."parentID", 'parents'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [41]: """
            CREATE TRIGGER "sqlitedata_icloud_after_update_on_modelAs"
            AFTER UPDATE ON "modelAs"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'modelAs', NULL, NULL
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [42]: """
            CREATE TRIGGER "sqlitedata_icloud_after_update_on_modelBs"
            AFTER UPDATE ON "modelBs"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'modelBs', "new"."modelAID", 'modelAs'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [43]: """
            CREATE TRIGGER "sqlitedata_icloud_after_update_on_modelCs"
            AFTER UPDATE ON "modelCs"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'modelCs', "new"."modelBID", 'modelBs'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [44]: """
            CREATE TRIGGER "sqlitedata_icloud_after_update_on_parents"
            AFTER UPDATE ON "parents"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'parents', NULL, NULL
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [45]: """
            CREATE TRIGGER "sqlitedata_icloud_after_update_on_reminderTags"
            AFTER UPDATE ON "reminderTags"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'reminderTags', NULL, NULL
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [46]: """
            CREATE TRIGGER "sqlitedata_icloud_after_update_on_reminders"
            AFTER UPDATE ON "reminders"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'reminders', "new"."remindersListID", 'remindersLists'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [47]: """
            CREATE TRIGGER "sqlitedata_icloud_after_update_on_remindersListAssets"
            AFTER UPDATE ON "remindersListAssets"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'remindersListAssets', "new"."remindersListID", 'remindersLists'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [48]: """
            CREATE TRIGGER "sqlitedata_icloud_after_update_on_remindersListPrivates"
            AFTER UPDATE ON "remindersListPrivates"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'remindersListPrivates', "new"."remindersListID", 'remindersLists'
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [49]: """
            CREATE TRIGGER "sqlitedata_icloud_after_update_on_remindersLists"
            AFTER UPDATE ON "remindersLists"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."id", 'remindersLists', NULL, NULL
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """,
            [50]: """
            CREATE TRIGGER "sqlitedata_icloud_after_update_on_tags"
            AFTER UPDATE ON "tags"
            FOR EACH ROW BEGIN
              INSERT INTO "sqlitedata_icloud_metadata"
              ("recordPrimaryKey", "recordType", "parentRecordPrimaryKey", "parentRecordType")
              SELECT "new"."title", 'tags', NULL, NULL
              ON CONFLICT ("recordPrimaryKey", "recordType")
              DO UPDATE SET "parentRecordPrimaryKey" = "excluded"."parentRecordPrimaryKey", "parentRecordType" = "excluded"."parentRecordType", "userModificationDate" = "excluded"."userModificationDate";
            END
            """
          ]
          """#
        }
      #endif

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
