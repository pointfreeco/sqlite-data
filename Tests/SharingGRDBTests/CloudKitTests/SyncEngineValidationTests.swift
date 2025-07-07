import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  struct SyncEngineValidationTests {
    @Test
    func userTriggerValidation() async throws {
      let error = try await #require(
        #expect(throws: InvalidUserTriggers.self) {
          var configuration = Configuration()
          configuration.foreignKeysEnabled = false
          let database = try DatabaseQueue(configuration: configuration)
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
            metadatabaseURL: URL.temporaryDirectory.appending(path: UUID().uuidString),
            tables: [RemindersList.self]
          )
        }
      )

      #expect(
        error.localizedDescription.hasPrefix(
          """
          Triggers must include 'WHEN NOT sqlitedata_icloud_syncEngineIsUpdatingRecord()' clause: \
          'non_temporary_trigger', 'temporary_trigger'
          """
        )
      )
    }

    @Test func doNotValidateTriggersOnNonSyncedTables() async throws {
      var configuration = Configuration()
      configuration.foreignKeysEnabled = false
      let database = try DatabaseQueue(configuration: configuration)
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
      let _ = try await SyncEngine.init(
        container: MockCloudContainer(
          containerIdentifier: "deadbeef",
          privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
          sharedCloudDatabase: MockCloudDatabase(databaseScope: .shared)
        ),
        userDatabase: UserDatabase(database: database),
        metadatabaseURL: URL.temporaryDirectory.appending(path: UUID().uuidString),
        tables: []
      )
    }
  }
}
