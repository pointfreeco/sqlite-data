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
      let recordTypes = try await database.write { db in
        try RecordType.all.fetchAll(db)
      }
      assertInlineSnapshot(of: recordTypes, as: .customDump) {
        #"""
        [
          [0]: RecordType(
            tableName: "remindersLists",
            schema: """
              CREATE TABLE "remindersLists" (
                "id" TEXT NOT NULL PRIMARY KEY DEFAULT (uuid()),
                "title" TEXT NOT NULL DEFAULT ''
              ) STRICT
              """
          ),
          [1]: RecordType(
            tableName: "users",
            schema: """
              CREATE TABLE "users" (
                "id" TEXT NOT NULL PRIMARY KEY DEFAULT (uuid()),
                "name" TEXT NOT NULL DEFAULT '',
                "parentUserID" TEXT,
              
                FOREIGN KEY("parentUserID") REFERENCES "users"("id") ON DELETE SET DEFAULT ON UPDATE CASCADE 
              ) STRICT
              """
          ),
          [2]: RecordType(
            tableName: "reminders",
            schema: """
              CREATE TABLE "reminders" (
                "id" TEXT NOT NULL PRIMARY KEY DEFAULT (uuid()),
                "assignedUserID" TEXT,
                "title" TEXT NOT NULL DEFAULT '',
                "parentReminderID" TEXT, 
                "remindersListID" TEXT NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000', 
                
                FOREIGN KEY("assignedUserID") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE,
                FOREIGN KEY("parentReminderID") REFERENCES "reminders"("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
                FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
              ) STRICT
              """
          )
        ]
        """#
      }
    }

    @Test func tearDown() async throws {
      try await syncEngine.tearDownSyncEngine()
      try await database.write { db in
        try #expect(RecordType.all.fetchAll(db) == [])
      }
    }

    @Test func resetUp() async throws {
      let recordTypes = try await database.write { db in
        try RecordType.all.fetchAll(db)
      }
      try await syncEngine.tearDownSyncEngine()
      try await syncEngine.setUpSyncEngine()
      privateSyncEngine.assertFetchChangesScopes([.all])
      sharedSyncEngine.assertFetchChangesScopes([.all])
      let recordTypesAfterReSetup = try await database.write { db in
        try RecordType.all.fetchAll(db)
      }
      expectNoDifference(recordTypes, recordTypesAfterReSetup)
    }

    @Test func migration() async throws {
      let recordTypes = try await database.write { db in
        try RecordType.all.fetchAll(db)
      }
      try await syncEngine.tearDownSyncEngine()
      try await database.write { db in
        try #sql(
          """
          ALTER TABLE "reminders" ADD COLUMN "newFeature" INTEGER NOT NULL 
          """
        )
        .execute(db)
      }
      try await syncEngine.setUpSyncEngine()
      privateSyncEngine.assertFetchChangesScopes([.all])
      sharedSyncEngine.assertFetchChangesScopes([.all])

      let recordTypesAfterMigration = try await database.write { db in
        try RecordType.all.fetchAll(db)
      }
      #expect(recordTypesAfterMigration.count == 3)
      #expect(recordTypes[0...1] == recordTypesAfterMigration[0...1])

      assertInlineSnapshot(of: recordTypesAfterMigration[2], as: .customDump) {
        #"""
        RecordType(
          tableName: "reminders",
          schema: """
            CREATE TABLE "reminders" (
              "id" TEXT NOT NULL PRIMARY KEY DEFAULT (uuid()),
              "assignedUserID" TEXT,
              "title" TEXT NOT NULL DEFAULT '',
              "parentReminderID" TEXT, 
              "remindersListID" TEXT NOT NULL DEFAULT '00000000-0000-0000-0000-000000000000', "newFeature" INTEGER NOT NULL, 
              
              FOREIGN KEY("assignedUserID") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE,
              FOREIGN KEY("parentReminderID") REFERENCES "reminders"("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
              FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
            ) STRICT
            """
        )
        """#
      }
    }
  }
}
