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

    @Test func initialSync() async throws {
      let metadata = try database.syncRead { db in
        try SyncMetadata.all.fetchAll(db)
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
      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(), syncEngine: privateSyncEngine
      )
      assertInlineSnapshot(of: batch, as: .customDump) {
        """
        CKSyncEngine.RecordZoneChangeBatch(
          atomicByZone: false,
          recordIDsToDelete: [],
          recordsToSave: [
            [0]: CKRecord(
              recordID: CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:reminders",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              ),
              recordType: "reminders",
              share: nil,
              parent: CKReference(
                recordID: CKRecordID(
                  recordName: "00000000-0000-0000-0000-000000000001:remindersLists",
                  zoneID: CKRecordZoneID(
                    zoneName: "co.pointfree.SQLiteData.defaultZone",
                    ownerName: "__defaultOwner__"
                  )
                )
              ),
              id: "00000000-0000-0000-0000-000000000001",
              remindersListID: "00000000-0000-0000-0000-000000000001",
              sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
              title: "Write blog post"
            ),
            [1]: CKRecord(
              recordID: CKRecordID(
                recordName: "00000000-0000-0000-0000-000000000001:remindersLists",
                zoneID: CKRecordZoneID(
                  zoneName: "co.pointfree.SQLiteData.defaultZone",
                  ownerName: "__defaultOwner__"
                )
              ),
              recordType: "remindersLists",
              share: nil,
              parent: nil,
              id: "00000000-0000-0000-0000-000000000001",
              sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
              title: "Personal"
            )
          ]
        )
        """
      }
    }
  }
}
