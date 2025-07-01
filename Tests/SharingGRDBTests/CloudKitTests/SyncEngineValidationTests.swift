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
            try RemindersList.createTemporaryTrigger(
              after: .delete { _ in
                RemindersList.insert {
                  RemindersList.Draft(title: "Personal")
                }
              } when: { _ in
                RemindersList.count().eq(0)
              }
            )
            .execute(db)
          }
          let _ = try await SyncEngine.init(
            container: MockCloudContainer(
              privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
              sharedCloudDatabase: MockCloudDatabase(databaseScope: .shared)
            ),
            userDatabase: UserDatabase(database: database),
            metadatabaseURL: URL.temporaryDirectory.appending(path: UUID().uuidString),
            tables: [
              RemindersList.self
            ]
          )
        }
      )

      #expect(
        error.localizedDescription.hasPrefix(
          """
          Triggers must include 'WHEN NOT sqlitedata_icloud_syncEngineIsUpdatingRecord()' clause: \
          'after_delete_on_remindersLists@SharingGRDBTests
          """
        )
      )
    }
  }
}
