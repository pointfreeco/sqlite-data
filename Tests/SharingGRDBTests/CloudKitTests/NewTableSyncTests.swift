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
        try SyncMetadata.order(by: \.recordName).fetchAll(db)
      }
      assertInlineSnapshot(of: metadata, as: .customDump) {
        """
        [
          [0]: SyncMetadata(
            recordPrimaryKey: "00000000-0000-0000-0000-000000000001",
            recordType: "reminders",
            recordName: "00000000-0000-0000-0000-000000000001:reminders",
            parentRecordPrimaryKey: "00000000-0000-0000-0000-000000000001",
            parentRecordType: "remindersLists",
            parentRecordName: "00000000-0000-0000-0000-000000000001:remindersLists",
            lastKnownServerRecord: CKRecord(
              recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
              recordType: "reminders",
              parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
              share: nil
            ),
            _lastKnownServerRecordAllFields: CKRecord(
              recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
              recordType: "reminders",
              parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
              share: nil,
              id: "00000000-0000-0000-0000-000000000001",
              isCompleted: 0,
              remindersListID: "00000000-0000-0000-0000-000000000001",
              title: "Write blog post"
            ),
            share: nil,
            isShared: false,
            userModificationDate: Date(1970-01-01T00:00:00.000Z)
          ),
          [1]: SyncMetadata(
            recordPrimaryKey: "00000000-0000-0000-0000-000000000001",
            recordType: "remindersLists",
            recordName: "00000000-0000-0000-0000-000000000001:remindersLists",
            parentRecordPrimaryKey: nil,
            parentRecordType: nil,
            parentRecordName: nil,
            lastKnownServerRecord: CKRecord(
              recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
              recordType: "remindersLists",
              parent: nil,
              share: nil
            ),
            _lastKnownServerRecordAllFields: CKRecord(
              recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
              recordType: "remindersLists",
              parent: nil,
              share: nil,
              id: "00000000-0000-0000-0000-000000000001",
              title: "Personal"
            ),
            share: nil,
            isShared: false,
            userModificationDate: Date(1970-01-01T00:00:00.000Z)
          )
        ]
        """
      }
    }
  }
}
