import CloudKit
import ConcurrencyExtras
import CustomDump
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class RecordTypeTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func setUp() async throws {
      let recordTypes = try database.syncWrite { db in
        try RecordType.all.fetchAll(db)
      }
      assertInlineSnapshot(of: recordTypes, as: .customDump) {
        #"""
        [
          [0]: RecordType(
            tableName: "remindersLists",
            schema: """
              CREATE TABLE "remindersLists" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "title" TEXT NOT NULL DEFAULT ''
              ) STRICT
              """
          ),
          [1]: RecordType(
            tableName: "remindersListPrivates",
            schema: """
              CREATE TABLE "remindersListPrivates" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "position" INTEGER NOT NULL DEFAULT 0,
                "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
              ) STRICT
              """
          ),
          [2]: RecordType(
            tableName: "users",
            schema: """
              CREATE TABLE "users" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "name" TEXT NOT NULL DEFAULT '',
                "parentUserID" TEXT,
              
                FOREIGN KEY("parentUserID") REFERENCES "users"("id") ON DELETE SET DEFAULT ON UPDATE CASCADE 
              ) STRICT
              """
          ),
          [3]: RecordType(
            tableName: "reminders",
            schema: """
              CREATE TABLE "reminders" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "title" TEXT NOT NULL DEFAULT '',
                "remindersListID" TEXT NOT NULL, 
                
                FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
              ) STRICT
              """
          ),
          [4]: RecordType(
            tableName: "tags",
            schema: """
              CREATE TABLE "tags" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "title" TEXT NOT NULL DEFAULT ''
              ) STRICT
              """
          ),
          [5]: RecordType(
            tableName: "reminderTags",
            schema: """
              CREATE TABLE "reminderTags" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "reminderID" TEXT NOT NULL REFERENCES "reminders"("id") ON DELETE CASCADE,
                "tagID" TEXT NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE
              ) STRICT
              """
          ),
          [6]: RecordType(
            tableName: "parents",
            schema: """
              CREATE TABLE "parents"(
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())
              ) STRICT
              """
          ),
          [7]: RecordType(
            tableName: "childWithOnDeleteRestricts",
            schema: """
              CREATE TABLE "childWithOnDeleteRestricts"(
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "parentID" TEXT NOT NULL REFERENCES "parents"("id") ON DELETE RESTRICT ON UPDATE RESTRICT
              ) STRICT
              """
          ),
          [8]: RecordType(
            tableName: "childWithOnDeleteSetNulls",
            schema: """
              CREATE TABLE "childWithOnDeleteSetNulls"(
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "parentID" TEXT REFERENCES "parents"("id") ON DELETE SET NULL ON UPDATE SET NULL
              ) STRICT
              """
          ),
          [9]: RecordType(
            tableName: "childWithOnDeleteSetDefaults",
            schema: """
              CREATE TABLE "childWithOnDeleteSetDefaults"(
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT '00000000-0000-0000-0000-000000000000',
                "parentID" TEXT REFERENCES "parents"("id") ON DELETE SET DEFAULT ON UPDATE SET DEFAULT
              ) STRICT
              """
          )
        ]
        """#
      }
    }

    @Test func tearDown() async throws {
      try await syncEngine.tearDownSyncEngine()
      try database.syncWrite { db in
        try #expect(RecordType.all.fetchAll(db) == [])
      }
    }

    @Test func resetUp() async throws {
      let recordTypes = try database.syncWrite { db in
        try RecordType.all.fetchAll(db)
      }
      try await syncEngine.tearDownSyncEngine()
      try await syncEngine.setUpSyncEngine()
      let recordTypesAfterReSetup = try database.syncWrite { db in
        try RecordType.all.fetchAll(db)
      }
      expectNoDifference(recordTypes, recordTypesAfterReSetup)
    }

    @Test func migration() async throws {
      let recordTypes = try database.syncWrite { db in
        try RecordType.order(by: \.tableName).fetchAll(db)
      }
      try await syncEngine.tearDownSyncEngine()
      try database.syncWrite { db in
        try #sql(
          """
          ALTER TABLE "reminders" ADD COLUMN "newFeature" INTEGER NOT NULL 
          """
        )
        .execute(db)
      }
      try await syncEngine.setUpSyncEngine()

      let recordTypesAfterMigration = try database.syncWrite { db in
        try RecordType.order(by: \.tableName).fetchAll(db)
      }
      let remindersTableIndex = try #require(
        recordTypesAfterMigration.firstIndex { $0.tableName == Reminder.tableName }
      )
      #expect(recordTypes[0..<remindersTableIndex] == recordTypesAfterMigration[0..<remindersTableIndex])
      #expect(recordTypes[(remindersTableIndex+1)...] == recordTypesAfterMigration[(remindersTableIndex+1)...])

      assertInlineSnapshot(of: recordTypesAfterMigration[remindersTableIndex], as: .customDump) {
        #"""
        RecordType(
          tableName: "reminders",
          schema: """
            CREATE TABLE "reminders" (
              "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
              "title" TEXT NOT NULL DEFAULT '',
              "remindersListID" TEXT NOT NULL, "newFeature" INTEGER NOT NULL, 
              
              FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
            ) STRICT
            """
        )
        """#
      }
    }
  }
}
