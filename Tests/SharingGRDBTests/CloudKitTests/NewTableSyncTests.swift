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
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                isCompleted: 0,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                title: "Write blog post"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
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

      let metadata = try await userDatabase.userRead { db in
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
            lastKnownServerRecord: CKRecord(
              recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
              recordType: "reminders",
              parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
              share: nil
            ),
            share: nil,
            userModificationDate: nil
          ),
          [1]: SyncMetadata(
            recordType: "remindersLists",
            recordName: SyncMetadata.RecordName(
              recordType: "remindersLists",
              id: UUID(00000000-0000-0000-0000-000000000001)
            ),
            parentRecordName: nil,
            lastKnownServerRecord: CKRecord(
              recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
              recordType: "remindersLists",
              parent: nil,
              share: nil
            ),
            share: nil,
            userModificationDate: nil
          )
        ]
        """
      }
    }
  }
}
