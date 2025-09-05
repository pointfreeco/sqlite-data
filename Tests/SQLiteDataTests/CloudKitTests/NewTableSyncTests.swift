#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import SQLiteDataTestSupport
  import Foundation
  import InlineSnapshotTesting
  import SQLiteData
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class NewTableSyncTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      init() async throws {
        try await super.init(
          setUpUserDatabase: { userDatabase in
            try await userDatabase.userWrite { db in
              try db.seed {
                RemindersList(id: 1, title: "Personal")
                Reminder(id: 1, title: "Write blog post", remindersListID: 1)
              }
            }
          }
        )
      }

      // * Create records before sync engine starts
      // => Records are sent to CloudKit
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func initialSync() async throws {
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                  recordType: "reminders",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                  share: nil,
                  id: 1,
                  isCompleted: 0,
                  remindersListID: 1,
                  title: "Write blog post"
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: "Personal"
                )
              ]
            ),
            sharedCloudDatabase: MockCloudDatabase(
              databaseScope: .shared,
              storage: []
            )
          )
          """
        }

        assertQuery(
          SyncMetadata.order(by: \.recordName).select(\.recordName),
          database: syncEngine.metadatabase
        ) {
          """
          ┌────────────────────┐
          │ "1:reminders"      │
          │ "1:remindersLists" │
          └────────────────────┘
          """
        }
      }
    }
  }
#endif
