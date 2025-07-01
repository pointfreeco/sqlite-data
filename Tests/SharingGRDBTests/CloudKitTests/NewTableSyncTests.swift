import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class NewTableSyncTests: BaseCloudKitTests, @unchecked Sendable {
    init() async throws {
      try await super.init(
        seeds: [
          RemindersList(id: UUID(1), title: "Personal"),
          Reminder(id: UUID(1), title: "Write blog post", remindersListID: UUID(1))
        ]
      )
    }

    @Test
    func initialSync() async throws {
      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: []
          ),
          sharedCloudDatabase: MockCloudDatabase(
            databaseScope: .shared,
            storage: []
          )
        )
        """
      }

      let metadata = try await database.userRead { db in
        try SyncMetadata.all.order(by: \.primaryKey).fetchAll(db)
      }
      assertInlineSnapshot(of: metadata, as: .customDump) {
        """
        [
          [0]: SyncMetadata(
            recordType: "reminders",
            recordName: SyncMetadata.RecordName(
              recordType: "reminders",
              id: UUID(00000000-0000-0000-0000-000000000001)
            ),
            parentRecordName: SyncMetadata.RecordName(
              recordType: "remindersLists",
              id: UUID(00000000-0000-0000-0000-000000000001)
            ),
            lastKnownServerRecord: nil,
            share: nil,
            userModificationDate: Date(2009-02-13T23:31:30.000Z)
          ),
          [1]: SyncMetadata(
            recordType: "remindersLists",
            recordName: SyncMetadata.RecordName(
              recordType: "remindersLists",
              id: UUID(00000000-0000-0000-0000-000000000001)
            ),
            parentRecordName: nil,
            lastKnownServerRecord: nil,
            share: nil,
            userModificationDate: Date(2009-02-13T23:31:30.000Z)
          )
        ]
        """
      }
    }
  }
}
