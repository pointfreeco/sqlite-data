import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @Table("invalid:table")
  struct InvalidTable {
    let id: UUID
  }

  @MainActor
  struct SyncEngineValidationTests {
    @Test func tableNameValidation() async throws {
      let error = try #require(
        await #expect(throws: InvalidTableName.self) {
          let database = try DatabaseQueue()
          _ = try await SyncEngine(
            container: MockCloudContainer(
              containerIdentifier: "deadbeef",
              privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
              sharedCloudDatabase: MockCloudDatabase(databaseScope: .shared)
            ),
            userDatabase: UserDatabase(database: database),
            tables: [InvalidTable.self]
          )
        }
      )
      #expect(
        error.localizedDescription.hasPrefix(
          """
          Table name "invalid:table" contains invalid character ':'.
          """
        )
      )
    }

    @Test func foreignKeyActionValidation() async throws {
      let error = try #require(
        await #expect(throws: InvalidParentForeignKey.self) {
          var configuration = Configuration()
          configuration.foreignKeysEnabled = false
          let database = try DatabaseQueue(configuration: configuration)
          try await database.write { db in
            try #sql(
              """
              CREATE TABLE "parents" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
              ) STRICT
              """
            )
            .execute(db)
            try #sql(
              """
              CREATE TABLE "children" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "parentID" INTEGER REFERENCES "parents"("id") ON DELETE NO ACTION
              ) STRICT
              """
            )
            .execute(db)
          }
          _ = try await SyncEngine(
            container: MockCloudContainer(
              containerIdentifier: "deadbeef",
              privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
              sharedCloudDatabase: MockCloudDatabase(databaseScope: .shared)
            ),
            userDatabase: UserDatabase(database: database),
            tables: []
          )
        }
      )
      #expect(
        error.localizedDescription ==
          """
          Foreign key "children"."parentID" action not supported. Must be 'CASCADE', 'SET DEFAULT' \
          or 'SET NULL'.
          """
      )
    }

    @Test func userTriggerValidation() async throws {
      let error = try await #require(
        #expect(throws: InvalidUserTriggers.self) {
          let database = try DatabaseQueue()
          try await database.write { db in
            try #sql(
              """
              CREATE TABLE "remindersLists" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "title" TEXT NOT NULL DEFAULT ''
              ) STRICT
              """
            )
            .execute(db)
            try #sql(
              """
              CREATE TRIGGER "non_temporary_trigger"
              AFTER UPDATE ON "remindersLists"
              FOR EACH ROW BEGIN
                SELECT 1;
              END
              """
            )
            .execute(db)
            try #sql(
              """
              CREATE TEMPORARY TRIGGER "temporary_trigger"
              AFTER UPDATE ON "remindersLists"
              FOR EACH ROW BEGIN
                SELECT 1;
              END
              """
            )
            .execute(db)
          }
          let _ = try await SyncEngine(
            container: MockCloudContainer(
              containerIdentifier: "deadbeef",
              privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
              sharedCloudDatabase: MockCloudDatabase(databaseScope: .shared)
            ),
            userDatabase: UserDatabase(database: database),
            tables: [RemindersList.self]
          )
        }
      )

      #expect(
        error.localizedDescription.hasPrefix(
          """
          Triggers must include 'sqlitedata_icloud_syncEngineIsSynchronizingChanges()' check: \
          'non_temporary_trigger', 'temporary_trigger'
          """
        )
      )
    }

    @Test func doNotValidateTriggersOnNonSyncedTables() async throws {
      let database = try DatabaseQueue()
      try await database.write { db in
        try #sql(
          """
          CREATE TABLE "remindersLists" (
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "title" TEXT NOT NULL DEFAULT ''
          ) STRICT
          """
        )
        .execute(db)
        try #sql(
          """
          CREATE TRIGGER "non_temporary_trigger"
          AFTER UPDATE ON "remindersLists"
          FOR EACH ROW BEGIN
            SELECT 1;
          END
          """
        )
        .execute(db)
        try #sql(
          """
          CREATE TEMPORARY TRIGGER "temporary_trigger"
          AFTER UPDATE ON "remindersLists"
          FOR EACH ROW BEGIN
            SELECT 1;
          END
          """
        )
        .execute(db)
      }
      let _ = try await SyncEngine(
        container: MockCloudContainer(
          containerIdentifier: "deadbeef",
          privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
          sharedCloudDatabase: MockCloudDatabase(databaseScope: .shared)
        ),
        userDatabase: UserDatabase(database: database),
        tables: []
      )
    }
  }
}
