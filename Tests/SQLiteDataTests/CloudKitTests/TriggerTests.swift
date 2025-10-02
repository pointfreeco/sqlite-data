#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import InlineSnapshotTesting
  import SQLiteData
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
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_childWithOnDeleteSetDefaults_from_sync_engine"
              AFTER DELETE ON "childWithOnDeleteSetDefaults"
              FOR EACH ROW WHEN "sqlitedata_icloud_syncEngineIsSynchronizingChanges"() BEGIN
                DELETE FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('childWithOnDeleteSetDefaults'));
              END
              """,
              [1]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_childWithOnDeleteSetDefaults_from_user"
              AFTER DELETE ON "childWithOnDeleteSetDefaults"
              FOR EACH ROW WHEN NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"()) BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("old"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('parents'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('childWithOnDeleteSetDefaults'));
              END
              """,
              [2]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_childWithOnDeleteSetNulls_from_sync_engine"
              AFTER DELETE ON "childWithOnDeleteSetNulls"
              FOR EACH ROW WHEN "sqlitedata_icloud_syncEngineIsSynchronizingChanges"() BEGIN
                DELETE FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('childWithOnDeleteSetNulls'));
              END
              """,
              [3]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_childWithOnDeleteSetNulls_from_user"
              AFTER DELETE ON "childWithOnDeleteSetNulls"
              FOR EACH ROW WHEN NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"()) BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("old"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('parents'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('childWithOnDeleteSetNulls'));
              END
              """,
              [4]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelAs_from_sync_engine"
              AFTER DELETE ON "modelAs"
              FOR EACH ROW WHEN "sqlitedata_icloud_syncEngineIsSynchronizingChanges"() BEGIN
                DELETE FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelAs'));
              END
              """,
              [5]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelAs_from_user"
              AFTER DELETE ON "modelAs"
              FOR EACH ROW WHEN NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"()) BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelAs'));
              END
              """,
              [6]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelBs_from_sync_engine"
              AFTER DELETE ON "modelBs"
              FOR EACH ROW WHEN "sqlitedata_icloud_syncEngineIsSynchronizingChanges"() BEGIN
                DELETE FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelBs'));
              END
              """,
              [7]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelBs_from_user"
              AFTER DELETE ON "modelBs"
              FOR EACH ROW WHEN NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"()) BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("old"."modelAID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('modelAs'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelBs'));
              END
              """,
              [8]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelCs_from_sync_engine"
              AFTER DELETE ON "modelCs"
              FOR EACH ROW WHEN "sqlitedata_icloud_syncEngineIsSynchronizingChanges"() BEGIN
                DELETE FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelCs'));
              END
              """,
              [9]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_modelCs_from_user"
              AFTER DELETE ON "modelCs"
              FOR EACH ROW WHEN NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"()) BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("old"."modelBID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('modelBs'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelCs'));
              END
              """,
              [10]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_parents_from_sync_engine"
              AFTER DELETE ON "parents"
              FOR EACH ROW WHEN "sqlitedata_icloud_syncEngineIsSynchronizingChanges"() BEGIN
                DELETE FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents'));
              END
              """,
              [11]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_parents_from_user"
              AFTER DELETE ON "parents"
              FOR EACH ROW WHEN NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"()) BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents'));
              END
              """,
              [12]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_reminderTags_from_sync_engine"
              AFTER DELETE ON "reminderTags"
              FOR EACH ROW WHEN "sqlitedata_icloud_syncEngineIsSynchronizingChanges"() BEGIN
                DELETE FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('reminderTags'));
              END
              """,
              [13]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_reminderTags_from_user"
              AFTER DELETE ON "reminderTags"
              FOR EACH ROW WHEN NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"()) BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('reminderTags'));
              END
              """,
              [14]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersListAssets_from_sync_engine"
              AFTER DELETE ON "remindersListAssets"
              FOR EACH ROW WHEN "sqlitedata_icloud_syncEngineIsSynchronizingChanges"() BEGIN
                DELETE FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersListAssets'));
              END
              """,
              [15]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersListAssets_from_user"
              AFTER DELETE ON "remindersListAssets"
              FOR EACH ROW WHEN NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"()) BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("old"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('remindersLists'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersListAssets'));
              END
              """,
              [16]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersListPrivates_from_sync_engine"
              AFTER DELETE ON "remindersListPrivates"
              FOR EACH ROW WHEN "sqlitedata_icloud_syncEngineIsSynchronizingChanges"() BEGIN
                DELETE FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersListPrivates'));
              END
              """,
              [17]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersListPrivates_from_user"
              AFTER DELETE ON "remindersListPrivates"
              FOR EACH ROW WHEN NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"()) BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("old"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('remindersLists'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersListPrivates'));
              END
              """,
              [18]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersLists_from_sync_engine"
              AFTER DELETE ON "remindersLists"
              FOR EACH ROW WHEN "sqlitedata_icloud_syncEngineIsSynchronizingChanges"() BEGIN
                DELETE FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists'));
              END
              """,
              [19]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_remindersLists_from_user"
              AFTER DELETE ON "remindersLists"
              FOR EACH ROW WHEN NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"()) BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists'));
              END
              """,
              [20]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_reminders_from_sync_engine"
              AFTER DELETE ON "reminders"
              FOR EACH ROW WHEN "sqlitedata_icloud_syncEngineIsSynchronizingChanges"() BEGIN
                DELETE FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('reminders'));
              END
              """,
              [21]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_reminders_from_user"
              AFTER DELETE ON "reminders"
              FOR EACH ROW WHEN NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"()) BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("old"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('remindersLists'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('reminders'));
              END
              """,
              [22]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_sqlitedata_icloud_metadata"
              AFTER UPDATE OF "_isDeleted" ON "sqlitedata_icloud_metadata"
              FOR EACH ROW WHEN ((NOT ("old"."_isDeleted")) AND ("new"."_isDeleted")) AND (NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) BEGIN
                SELECT "sqlitedata_icloud_didDelete"("new"."recordName", coalesce("new"."lastKnownServerRecord", (
                  WITH "ancestorMetadatas" AS (
                    SELECT "sqlitedata_icloud_metadata"."recordName" AS "recordName", "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."lastKnownServerRecord" AS "lastKnownServerRecord"
                    FROM "sqlitedata_icloud_metadata"
                    WHERE ("sqlitedata_icloud_metadata"."recordName") = ("new"."recordName")
                      UNION ALL
                    SELECT "sqlitedata_icloud_metadata"."recordName" AS "recordName", "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."lastKnownServerRecord" AS "lastKnownServerRecord"
                    FROM "sqlitedata_icloud_metadata"
                    JOIN "ancestorMetadatas" ON ("sqlitedata_icloud_metadata"."recordName") IS ("ancestorMetadatas"."parentRecordName")
                  )
                  SELECT "ancestorMetadatas"."lastKnownServerRecord"
                  FROM "ancestorMetadatas"
                  WHERE ("ancestorMetadatas"."parentRecordName") IS (NULL)
                )), "new"."share");
              END
              """,
              [23]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_tags_from_sync_engine"
              AFTER DELETE ON "tags"
              FOR EACH ROW WHEN "sqlitedata_icloud_syncEngineIsSynchronizingChanges"() BEGIN
                DELETE FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."title")) AND (("sqlitedata_icloud_metadata"."recordType") = ('tags'));
              END
              """,
              [24]: """
              CREATE TRIGGER "sqlitedata_icloud_after_delete_on_tags_from_user"
              AFTER DELETE ON "tags"
              FOR EACH ROW WHEN NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"()) BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."title")) AND (("sqlitedata_icloud_metadata"."recordType") = ('tags'));
              END
              """,
              [25]: """
              CREATE TRIGGER "sqlitedata_icloud_after_insert_on_childWithOnDeleteSetDefaults"
              AFTER INSERT ON "childWithOnDeleteSetDefaults"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('parents'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'childWithOnDeleteSetDefaults', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents')))), '__defaultOwner__'), "new"."parentID", 'parents'
                ON CONFLICT DO NOTHING;
              END
              """,
              [26]: """
              CREATE TRIGGER "sqlitedata_icloud_after_insert_on_childWithOnDeleteSetNulls"
              AFTER INSERT ON "childWithOnDeleteSetNulls"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('parents'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'childWithOnDeleteSetNulls', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents')))), '__defaultOwner__'), "new"."parentID", 'parents'
                ON CONFLICT DO NOTHING;
              END
              """,
              [27]: """
              CREATE TRIGGER "sqlitedata_icloud_after_insert_on_modelAs"
              AFTER INSERT ON "modelAs"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'modelAs', coalesce("sqlitedata_icloud_currentZoneName"(), 'zone'), coalesce("sqlitedata_icloud_currentOwnerName"(), '__defaultOwner__'), NULL, NULL
                ON CONFLICT DO NOTHING;
              END
              """,
              [28]: """
              CREATE TRIGGER "sqlitedata_icloud_after_insert_on_modelBs"
              AFTER INSERT ON "modelBs"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."modelAID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('modelAs'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'modelBs', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."modelAID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelAs')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."modelAID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelAs')))), '__defaultOwner__'), "new"."modelAID", 'modelAs'
                ON CONFLICT DO NOTHING;
              END
              """,
              [29]: """
              CREATE TRIGGER "sqlitedata_icloud_after_insert_on_modelCs"
              AFTER INSERT ON "modelCs"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."modelBID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('modelBs'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'modelCs', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."modelBID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelBs')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."modelBID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelBs')))), '__defaultOwner__'), "new"."modelBID", 'modelBs'
                ON CONFLICT DO NOTHING;
              END
              """,
              [30]: """
              CREATE TRIGGER "sqlitedata_icloud_after_insert_on_parents"
              AFTER INSERT ON "parents"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'parents', coalesce("sqlitedata_icloud_currentZoneName"(), 'zone'), coalesce("sqlitedata_icloud_currentOwnerName"(), '__defaultOwner__'), NULL, NULL
                ON CONFLICT DO NOTHING;
              END
              """,
              [31]: """
              CREATE TRIGGER "sqlitedata_icloud_after_insert_on_reminderTags"
              AFTER INSERT ON "reminderTags"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'reminderTags', coalesce("sqlitedata_icloud_currentZoneName"(), 'zone'), coalesce("sqlitedata_icloud_currentOwnerName"(), '__defaultOwner__'), NULL, NULL
                ON CONFLICT DO NOTHING;
              END
              """,
              [32]: """
              CREATE TRIGGER "sqlitedata_icloud_after_insert_on_reminders"
              AFTER INSERT ON "reminders"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('remindersLists'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'reminders', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), '__defaultOwner__'), "new"."remindersListID", 'remindersLists'
                ON CONFLICT DO NOTHING;
              END
              """,
              [33]: """
              CREATE TRIGGER "sqlitedata_icloud_after_insert_on_remindersListAssets"
              AFTER INSERT ON "remindersListAssets"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('remindersLists'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."remindersListID", 'remindersListAssets', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), '__defaultOwner__'), "new"."remindersListID", 'remindersLists'
                ON CONFLICT DO NOTHING;
              END
              """,
              [34]: """
              CREATE TRIGGER "sqlitedata_icloud_after_insert_on_remindersListPrivates"
              AFTER INSERT ON "remindersListPrivates"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('remindersLists'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'remindersListPrivates', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), '__defaultOwner__'), "new"."remindersListID", 'remindersLists'
                ON CONFLICT DO NOTHING;
              END
              """,
              [35]: """
              CREATE TRIGGER "sqlitedata_icloud_after_insert_on_remindersLists"
              AFTER INSERT ON "remindersLists"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'remindersLists', coalesce("sqlitedata_icloud_currentZoneName"(), 'zone'), coalesce("sqlitedata_icloud_currentOwnerName"(), '__defaultOwner__'), NULL, NULL
                ON CONFLICT DO NOTHING;
              END
              """,
              [36]: """
              CREATE TRIGGER "sqlitedata_icloud_after_insert_on_sqlitedata_icloud_metadata"
              AFTER INSERT ON "sqlitedata_icloud_metadata"
              FOR EACH ROW WHEN NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"()) BEGIN
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.invalid-record-name-error')
                WHERE NOT (((substr("new"."recordName", 1, 1)) <> ('_')) AND ((octet_length("new"."recordName")) <= (255))) AND ((octet_length("new"."recordName")) = (length("new"."recordName")));
                SELECT "sqlitedata_icloud_didUpdate"("new"."recordName", "new"."zoneName", "new"."ownerName", "new"."zoneName", "new"."ownerName", NULL);
              END
              """,
              [37]: """
              CREATE TRIGGER "sqlitedata_icloud_after_insert_on_tags"
              AFTER INSERT ON "tags"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."title", 'tags', coalesce("sqlitedata_icloud_currentZoneName"(), 'zone'), coalesce("sqlitedata_icloud_currentOwnerName"(), '__defaultOwner__'), NULL, NULL
                ON CONFLICT DO NOTHING;
              END
              """,
              [38]: """
              CREATE TRIGGER "sqlitedata_icloud_after_primary_key_change_on_childWithOnDeleteSetDefaults"
              AFTER UPDATE OF "id" ON "childWithOnDeleteSetDefaults"
              FOR EACH ROW WHEN ("old"."id") <> ("new"."id") BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('parents'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('childWithOnDeleteSetDefaults'));
              END
              """,
              [39]: """
              CREATE TRIGGER "sqlitedata_icloud_after_primary_key_change_on_childWithOnDeleteSetNulls"
              AFTER UPDATE OF "id" ON "childWithOnDeleteSetNulls"
              FOR EACH ROW WHEN ("old"."id") <> ("new"."id") BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('parents'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('childWithOnDeleteSetNulls'));
              END
              """,
              [40]: """
              CREATE TRIGGER "sqlitedata_icloud_after_primary_key_change_on_modelAs"
              AFTER UPDATE OF "id" ON "modelAs"
              FOR EACH ROW WHEN ("old"."id") <> ("new"."id") BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelAs'));
              END
              """,
              [41]: """
              CREATE TRIGGER "sqlitedata_icloud_after_primary_key_change_on_modelBs"
              AFTER UPDATE OF "id" ON "modelBs"
              FOR EACH ROW WHEN ("old"."id") <> ("new"."id") BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."modelAID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('modelAs'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelBs'));
              END
              """,
              [42]: """
              CREATE TRIGGER "sqlitedata_icloud_after_primary_key_change_on_modelCs"
              AFTER UPDATE OF "id" ON "modelCs"
              FOR EACH ROW WHEN ("old"."id") <> ("new"."id") BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."modelBID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('modelBs'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelCs'));
              END
              """,
              [43]: """
              CREATE TRIGGER "sqlitedata_icloud_after_primary_key_change_on_parents"
              AFTER UPDATE OF "id" ON "parents"
              FOR EACH ROW WHEN ("old"."id") <> ("new"."id") BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents'));
              END
              """,
              [44]: """
              CREATE TRIGGER "sqlitedata_icloud_after_primary_key_change_on_reminderTags"
              AFTER UPDATE OF "id" ON "reminderTags"
              FOR EACH ROW WHEN ("old"."id") <> ("new"."id") BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('reminderTags'));
              END
              """,
              [45]: """
              CREATE TRIGGER "sqlitedata_icloud_after_primary_key_change_on_reminders"
              AFTER UPDATE OF "id" ON "reminders"
              FOR EACH ROW WHEN ("old"."id") <> ("new"."id") BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('remindersLists'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('reminders'));
              END
              """,
              [46]: """
              CREATE TRIGGER "sqlitedata_icloud_after_primary_key_change_on_remindersListAssets"
              AFTER UPDATE OF "remindersListID" ON "remindersListAssets"
              FOR EACH ROW WHEN ("old"."remindersListID") <> ("new"."remindersListID") BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('remindersLists'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersListAssets'));
              END
              """,
              [47]: """
              CREATE TRIGGER "sqlitedata_icloud_after_primary_key_change_on_remindersListPrivates"
              AFTER UPDATE OF "id" ON "remindersListPrivates"
              FOR EACH ROW WHEN ("old"."id") <> ("new"."id") BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('remindersLists'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersListPrivates'));
              END
              """,
              [48]: """
              CREATE TRIGGER "sqlitedata_icloud_after_primary_key_change_on_remindersLists"
              AFTER UPDATE OF "id" ON "remindersLists"
              FOR EACH ROW WHEN ("old"."id") <> ("new"."id") BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists'));
              END
              """,
              [49]: """
              CREATE TRIGGER "sqlitedata_icloud_after_primary_key_change_on_tags"
              AFTER UPDATE OF "title" ON "tags"
              FOR EACH ROW WHEN ("old"."title") <> ("new"."title") BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                UPDATE "sqlitedata_icloud_metadata"
                SET "_isDeleted" = 1
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("old"."title")) AND (("sqlitedata_icloud_metadata"."recordType") = ('tags'));
              END
              """,
              [50]: """
              CREATE TRIGGER "sqlitedata_icloud_after_update_on_childWithOnDeleteSetDefaults"
              AFTER UPDATE ON "childWithOnDeleteSetDefaults"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('parents'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'childWithOnDeleteSetDefaults', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents')))), '__defaultOwner__'), "new"."parentID", 'parents'
                ON CONFLICT DO NOTHING;
                UPDATE "sqlitedata_icloud_metadata"
                SET "zoneName" = coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents')))), "sqlitedata_icloud_metadata"."zoneName"), "ownerName" = coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents')))), "sqlitedata_icloud_metadata"."ownerName"), "parentRecordPrimaryKey" = "new"."parentID", "parentRecordType" = 'parents', "userModificationTime" = "sqlitedata_icloud_currentTime"()
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('childWithOnDeleteSetDefaults'));
              END
              """,
              [51]: """
              CREATE TRIGGER "sqlitedata_icloud_after_update_on_childWithOnDeleteSetNulls"
              AFTER UPDATE ON "childWithOnDeleteSetNulls"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('parents'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'childWithOnDeleteSetNulls', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents')))), '__defaultOwner__'), "new"."parentID", 'parents'
                ON CONFLICT DO NOTHING;
                UPDATE "sqlitedata_icloud_metadata"
                SET "zoneName" = coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents')))), "sqlitedata_icloud_metadata"."zoneName"), "ownerName" = coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."parentID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents')))), "sqlitedata_icloud_metadata"."ownerName"), "parentRecordPrimaryKey" = "new"."parentID", "parentRecordType" = 'parents', "userModificationTime" = "sqlitedata_icloud_currentTime"()
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('childWithOnDeleteSetNulls'));
              END
              """,
              [52]: """
              CREATE TRIGGER "sqlitedata_icloud_after_update_on_modelAs"
              AFTER UPDATE ON "modelAs"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'modelAs', coalesce("sqlitedata_icloud_currentZoneName"(), 'zone'), coalesce("sqlitedata_icloud_currentOwnerName"(), '__defaultOwner__'), NULL, NULL
                ON CONFLICT DO NOTHING;
                UPDATE "sqlitedata_icloud_metadata"
                SET "zoneName" = coalesce("sqlitedata_icloud_currentZoneName"(), "sqlitedata_icloud_metadata"."zoneName"), "ownerName" = coalesce("sqlitedata_icloud_currentOwnerName"(), "sqlitedata_icloud_metadata"."ownerName"), "parentRecordPrimaryKey" = NULL, "parentRecordType" = NULL, "userModificationTime" = "sqlitedata_icloud_currentTime"()
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelAs'));
              END
              """,
              [53]: """
              CREATE TRIGGER "sqlitedata_icloud_after_update_on_modelBs"
              AFTER UPDATE ON "modelBs"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."modelAID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('modelAs'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'modelBs', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."modelAID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelAs')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."modelAID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelAs')))), '__defaultOwner__'), "new"."modelAID", 'modelAs'
                ON CONFLICT DO NOTHING;
                UPDATE "sqlitedata_icloud_metadata"
                SET "zoneName" = coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."modelAID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelAs')))), "sqlitedata_icloud_metadata"."zoneName"), "ownerName" = coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."modelAID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelAs')))), "sqlitedata_icloud_metadata"."ownerName"), "parentRecordPrimaryKey" = "new"."modelAID", "parentRecordType" = 'modelAs', "userModificationTime" = "sqlitedata_icloud_currentTime"()
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelBs'));
              END
              """,
              [54]: """
              CREATE TRIGGER "sqlitedata_icloud_after_update_on_modelCs"
              AFTER UPDATE ON "modelCs"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."modelBID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('modelBs'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'modelCs', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."modelBID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelBs')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."modelBID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelBs')))), '__defaultOwner__'), "new"."modelBID", 'modelBs'
                ON CONFLICT DO NOTHING;
                UPDATE "sqlitedata_icloud_metadata"
                SET "zoneName" = coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."modelBID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelBs')))), "sqlitedata_icloud_metadata"."zoneName"), "ownerName" = coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."modelBID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelBs')))), "sqlitedata_icloud_metadata"."ownerName"), "parentRecordPrimaryKey" = "new"."modelBID", "parentRecordType" = 'modelBs', "userModificationTime" = "sqlitedata_icloud_currentTime"()
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('modelCs'));
              END
              """,
              [55]: """
              CREATE TRIGGER "sqlitedata_icloud_after_update_on_parents"
              AFTER UPDATE ON "parents"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'parents', coalesce("sqlitedata_icloud_currentZoneName"(), 'zone'), coalesce("sqlitedata_icloud_currentOwnerName"(), '__defaultOwner__'), NULL, NULL
                ON CONFLICT DO NOTHING;
                UPDATE "sqlitedata_icloud_metadata"
                SET "zoneName" = coalesce("sqlitedata_icloud_currentZoneName"(), "sqlitedata_icloud_metadata"."zoneName"), "ownerName" = coalesce("sqlitedata_icloud_currentOwnerName"(), "sqlitedata_icloud_metadata"."ownerName"), "parentRecordPrimaryKey" = NULL, "parentRecordType" = NULL, "userModificationTime" = "sqlitedata_icloud_currentTime"()
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('parents'));
              END
              """,
              [56]: """
              CREATE TRIGGER "sqlitedata_icloud_after_update_on_reminderTags"
              AFTER UPDATE ON "reminderTags"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'reminderTags', coalesce("sqlitedata_icloud_currentZoneName"(), 'zone'), coalesce("sqlitedata_icloud_currentOwnerName"(), '__defaultOwner__'), NULL, NULL
                ON CONFLICT DO NOTHING;
                UPDATE "sqlitedata_icloud_metadata"
                SET "zoneName" = coalesce("sqlitedata_icloud_currentZoneName"(), "sqlitedata_icloud_metadata"."zoneName"), "ownerName" = coalesce("sqlitedata_icloud_currentOwnerName"(), "sqlitedata_icloud_metadata"."ownerName"), "parentRecordPrimaryKey" = NULL, "parentRecordType" = NULL, "userModificationTime" = "sqlitedata_icloud_currentTime"()
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('reminderTags'));
              END
              """,
              [57]: """
              CREATE TRIGGER "sqlitedata_icloud_after_update_on_reminders"
              AFTER UPDATE ON "reminders"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('remindersLists'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'reminders', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), '__defaultOwner__'), "new"."remindersListID", 'remindersLists'
                ON CONFLICT DO NOTHING;
                UPDATE "sqlitedata_icloud_metadata"
                SET "zoneName" = coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), "sqlitedata_icloud_metadata"."zoneName"), "ownerName" = coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), "sqlitedata_icloud_metadata"."ownerName"), "parentRecordPrimaryKey" = "new"."remindersListID", "parentRecordType" = 'remindersLists', "userModificationTime" = "sqlitedata_icloud_currentTime"()
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('reminders'));
              END
              """,
              [58]: """
              CREATE TRIGGER "sqlitedata_icloud_after_update_on_remindersListAssets"
              AFTER UPDATE ON "remindersListAssets"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('remindersLists'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."remindersListID", 'remindersListAssets', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), '__defaultOwner__'), "new"."remindersListID", 'remindersLists'
                ON CONFLICT DO NOTHING;
                UPDATE "sqlitedata_icloud_metadata"
                SET "zoneName" = coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), "sqlitedata_icloud_metadata"."zoneName"), "ownerName" = coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), "sqlitedata_icloud_metadata"."ownerName"), "parentRecordPrimaryKey" = "new"."remindersListID", "parentRecordType" = 'remindersLists', "userModificationTime" = "sqlitedata_icloud_currentTime"()
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersListAssets'));
              END
              """,
              [59]: """
              CREATE TRIGGER "sqlitedata_icloud_after_update_on_remindersListPrivates"
              AFTER UPDATE ON "remindersListPrivates"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") IS ('remindersLists'))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'remindersListPrivates', coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), 'zone'), coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), '__defaultOwner__'), "new"."remindersListID", 'remindersLists'
                ON CONFLICT DO NOTHING;
                UPDATE "sqlitedata_icloud_metadata"
                SET "zoneName" = coalesce(coalesce("sqlitedata_icloud_currentZoneName"(), (SELECT "sqlitedata_icloud_metadata"."zoneName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), "sqlitedata_icloud_metadata"."zoneName"), "ownerName" = coalesce(coalesce("sqlitedata_icloud_currentOwnerName"(), (SELECT "sqlitedata_icloud_metadata"."ownerName"
                FROM "sqlitedata_icloud_metadata"
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."remindersListID")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists')))), "sqlitedata_icloud_metadata"."ownerName"), "parentRecordPrimaryKey" = "new"."remindersListID", "parentRecordType" = 'remindersLists', "userModificationTime" = "sqlitedata_icloud_currentTime"()
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersListPrivates'));
              END
              """,
              [60]: """
              CREATE TRIGGER "sqlitedata_icloud_after_update_on_remindersLists"
              AFTER UPDATE ON "remindersLists"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."id", 'remindersLists', coalesce("sqlitedata_icloud_currentZoneName"(), 'zone'), coalesce("sqlitedata_icloud_currentOwnerName"(), '__defaultOwner__'), NULL, NULL
                ON CONFLICT DO NOTHING;
                UPDATE "sqlitedata_icloud_metadata"
                SET "zoneName" = coalesce("sqlitedata_icloud_currentZoneName"(), "sqlitedata_icloud_metadata"."zoneName"), "ownerName" = coalesce("sqlitedata_icloud_currentOwnerName"(), "sqlitedata_icloud_metadata"."ownerName"), "parentRecordPrimaryKey" = NULL, "parentRecordType" = NULL, "userModificationTime" = "sqlitedata_icloud_currentTime"()
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."id")) AND (("sqlitedata_icloud_metadata"."recordType") = ('remindersLists'));
              END
              """,
              [61]: """
              CREATE TRIGGER "sqlitedata_icloud_after_update_on_sqlitedata_icloud_metadata"
              AFTER UPDATE ON "sqlitedata_icloud_metadata"
              FOR EACH ROW WHEN (("old"."_isDeleted") = ("new"."_isDeleted")) AND (NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) BEGIN
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.invalid-record-name-error')
                WHERE NOT (((substr("new"."recordName", 1, 1)) <> ('_')) AND ((octet_length("new"."recordName")) <= (255))) AND ((octet_length("new"."recordName")) = (length("new"."recordName")));
                SELECT "sqlitedata_icloud_didUpdate"("new"."recordName", "new"."zoneName", "new"."ownerName", "old"."zoneName", "old"."ownerName", CASE WHEN (("new"."zoneName") <> ("old"."zoneName")) OR (("new"."ownerName") <> ("old"."ownerName")) THEN (
                  WITH "descendantMetadatas" AS (
                    SELECT "sqlitedata_icloud_metadata"."recordName" AS "recordName", NULL AS "parentRecordName"
                    FROM "sqlitedata_icloud_metadata"
                    WHERE ("sqlitedata_icloud_metadata"."recordName") = ("new"."recordName")
                      UNION ALL
                    SELECT "sqlitedata_icloud_metadata"."recordName" AS "recordName", "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName"
                    FROM "sqlitedata_icloud_metadata"
                    JOIN "descendantMetadatas" ON ("sqlitedata_icloud_metadata"."parentRecordName") = ("descendantMetadatas"."recordName")
                  )
                  SELECT json_group_array("descendantMetadatas"."recordName")
                  FROM "descendantMetadatas"
                  WHERE ("descendantMetadatas"."recordName") <> ("new"."recordName")
                ) END);
              END
              """,
              [62]: """
              CREATE TRIGGER "sqlitedata_icloud_after_update_on_tags"
              AFTER UPDATE ON "tags"
              FOR EACH ROW BEGIN
                WITH "rootShares" AS (
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") IS (NULL)) AND (("sqlitedata_icloud_metadata"."recordType") IS (NULL))
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName", "sqlitedata_icloud_metadata"."share" AS "share"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "rootShares" ON ("sqlitedata_icloud_metadata"."recordName") IS ("rootShares"."parentRecordName")
                )
                SELECT RAISE(ABORT, 'co.pointfree.SQLiteData.CloudKit.write-permission-error')
                FROM "rootShares"
                WHERE ((NOT ("sqlitedata_icloud_syncEngineIsSynchronizingChanges"())) AND (("rootShares"."parentRecordName") IS (NULL))) AND (NOT ("sqlitedata_icloud_hasPermission"("rootShares"."share")));
                INSERT INTO "sqlitedata_icloud_metadata"
                ("recordPrimaryKey", "recordType", "zoneName", "ownerName", "parentRecordPrimaryKey", "parentRecordType")
                SELECT "new"."title", 'tags', coalesce("sqlitedata_icloud_currentZoneName"(), 'zone'), coalesce("sqlitedata_icloud_currentOwnerName"(), '__defaultOwner__'), NULL, NULL
                ON CONFLICT DO NOTHING;
                UPDATE "sqlitedata_icloud_metadata"
                SET "zoneName" = coalesce("sqlitedata_icloud_currentZoneName"(), "sqlitedata_icloud_metadata"."zoneName"), "ownerName" = coalesce("sqlitedata_icloud_currentOwnerName"(), "sqlitedata_icloud_metadata"."ownerName"), "parentRecordPrimaryKey" = NULL, "parentRecordType" = NULL, "userModificationTime" = "sqlitedata_icloud_currentTime"()
                WHERE (("sqlitedata_icloud_metadata"."recordPrimaryKey") = ("new"."title")) AND (("sqlitedata_icloud_metadata"."recordType") = ('tags'));
              END
              """,
              [63]: """
              CREATE TRIGGER "sqlitedata_icloud_after_zone_update_on_sqlitedata_icloud_metadata"
              AFTER UPDATE OF "zoneName", "ownerName" ON "sqlitedata_icloud_metadata"
              FOR EACH ROW WHEN (("new"."zoneName") <> ("old"."zoneName")) OR (("new"."ownerName") <> ("old"."ownerName")) BEGIN
                UPDATE "sqlitedata_icloud_metadata"
                SET "zoneName" = "new"."zoneName", "ownerName" = "new"."ownerName", "lastKnownServerRecord" = NULL, "_lastKnownServerRecordAllFields" = NULL
                WHERE ("sqlitedata_icloud_metadata"."recordName") IN ((WITH "descendantMetadatas" AS (
                  SELECT "sqlitedata_icloud_metadata"."recordName" AS "recordName", NULL AS "parentRecordName"
                  FROM "sqlitedata_icloud_metadata"
                  WHERE ("sqlitedata_icloud_metadata"."recordName") = ("new"."recordName")
                    UNION ALL
                  SELECT "sqlitedata_icloud_metadata"."recordName" AS "recordName", "sqlitedata_icloud_metadata"."parentRecordName" AS "parentRecordName"
                  FROM "sqlitedata_icloud_metadata"
                  JOIN "descendantMetadatas" ON ("sqlitedata_icloud_metadata"."parentRecordName") = ("descendantMetadatas"."recordName")
                )
                SELECT "descendantMetadatas"."recordName"
                FROM "descendantMetadatas"));
              END
              """
            ]
            """#
          }
        #endif

        try syncEngine.tearDownSyncEngine()
        let triggersAfterTearDown = try await userDatabase.userWrite { db in
          try #sql("SELECT sql FROM sqlite_temp_master", as: String?.self).fetchAll(db)
        }
        assertInlineSnapshot(of: triggersAfterTearDown, as: .customDump) {
          """
          []
          """
        }

        try syncEngine.setUpSyncEngine()
        try await syncEngine.start()
        let triggersAfterReSetUp = try await userDatabase.userWrite { db in
          try #sql("SELECT sql FROM sqlite_temp_master ORDER BY sql", as: String?.self).fetchAll(db)
        }
        expectNoDifference(triggersAfterReSetUp, triggersAfterSetUp)
      }
    }
  }
#endif
