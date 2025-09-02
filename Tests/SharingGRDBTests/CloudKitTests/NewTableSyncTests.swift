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

      let metadata = try await userDatabase.userRead { db in
        try SyncMetadata.order(by: \.recordName).fetchAll(db)
      }
      assertInlineSnapshot(of: metadata, as: .customDump) {
        """
        [
          [0]: SyncMetadata(
            recordPrimaryKey: "1",
            recordType: "reminders",
            recordName: "1:reminders",
            parentRecordPrimaryKey: "1",
            parentRecordType: "remindersLists",
            parentRecordName: "1:remindersLists",
            lastKnownServerRecord: CKRecord(
              recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
              recordType: "reminders",
              parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
              share: nil
            ),
            _lastKnownServerRecordAllFields: CKRecord(
              recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
              recordType: "reminders",
              parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
              share: nil,
              id: 1,
              isCompleted: 0,
              remindersListID: 1,
              title: "Write blog post"
            ),
            share: nil,
            _isDeleted: false,
            isShared: false,
            userModificationDate: Date(1970-01-01T00:00:00.000Z)
          ),
          [1]: SyncMetadata(
            recordPrimaryKey: "1",
            recordType: "remindersLists",
            recordName: "1:remindersLists",
            parentRecordPrimaryKey: nil,
            parentRecordType: nil,
            parentRecordName: nil,
            lastKnownServerRecord: CKRecord(
              recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
              recordType: "remindersLists",
              parent: nil,
              share: nil
            ),
            _lastKnownServerRecordAllFields: CKRecord(
              recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
              recordType: "remindersLists",
              parent: nil,
              share: nil,
              id: 1,
              title: "Personal"
            ),
            share: nil,
            _isDeleted: false,
            isShared: false,
            userModificationDate: Date(1970-01-01T00:00:00.000Z)
          )
        ]
        """
      }
    }
  }
}
