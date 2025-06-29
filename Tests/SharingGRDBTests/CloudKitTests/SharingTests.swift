import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import OrderedCollections
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class SharingTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareNonRootRecord() async throws {
      let reminder = Reminder(id: UUID(1), title: "Groceries", remindersListID: UUID(1))
      let user = User(id: UUID(1))
      try await database.asyncWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          reminder
          user
        }
      }
      syncEngine.private.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1))),
        .saveRecord(Reminder.recordID(for: UUID(1))),
        .saveRecord(User.recordID(for: UUID(1))),
      ])

      await #expect(throws: SyncEngine.RecordMustBeRoot.self) {
        _ = try await self.syncEngine.share(record: reminder, configure: { _ in })
      }
      await #expect(throws: SyncEngine.RecordMustBeRoot.self) {
        _ = try await self.syncEngine.share(record: user, configure: { _ in })
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareUnrecognizedTable() async throws {
      await #expect(throws: SyncEngine.UnrecognizedTable.self) {
        _ = try await self.syncEngine.share(
          record: NonSyncedTable(id: UUID()),
          configure: { _ in }
        )
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func sharePrivateTable() async throws {
      await #expect(throws: SyncEngine.PrivateRootRecord.self) {
        _ = try await self.syncEngine.share(
          record: RemindersListPrivate(id: UUID(1), remindersListID: UUID(1)),
          configure: { _ in }
        )
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareRecordBeforeSync() async throws {
      await #expect(throws: SyncEngine.NoCKRecordFound.self) {
        _ = try await self.syncEngine.share(
          record: RemindersList(id: UUID(1)),
          configure: { _ in }
        )
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func createRecordInExternallySharedRecord() async throws {
      let externalZoneID = CKRecordZone.ID(
        zoneName: "external.zone",
        ownerName: "external.owner"
      )

      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: UUID(1), zoneID: externalZoneID)
      )
      remindersListRecord.encryptedValues["id"] = UUID(1).uuidString.lowercased()
      remindersListRecord.encryptedValues["isCompleted"] = false
      remindersListRecord.encryptedValues["title"] = "Personal"
      remindersListRecord.userModificationDate = Date(timeIntervalSince1970: 1_234_567_890)
      await syncEngine.handleFetchedRecordZoneChanges(
        modifications: [remindersListRecord],
        deletions: [],
        syncEngine: syncEngine.private
      )

      try await database.asyncWrite { db in
        try db.seed {
          Reminder(id: UUID(1), title: "Get milk", remindersListID: UUID(1))
        }
      }

      let batch = await syncEngine.nextRecordZoneChangeBatch(
        options: CKSyncEngine.SendChangesOptions(
          scope: .recordIDs([Reminder.recordID(for: UUID(1), zoneID: externalZoneID)])
        ),
        syncEngine: syncEngine.shared
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
                  zoneName: "external.zone",
                  ownerName: "external.owner"
                )
              ),
              recordType: "reminders",
              share: nil,
              parent: CKReference(
                recordID: CKRecordID(
                  recordName: "00000000-0000-0000-0000-000000000001:remindersLists",
                  zoneID: CKRecordZoneID(
                    zoneName: "external.zone",
                    ownerName: "external.owner"
                  )
                )
              ),
              id: "00000000-0000-0000-0000-000000000001",
              remindersListID: "00000000-0000-0000-0000-000000000001",
              sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
              title: "Get milk"
            )
          ]
        )
        """
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteRecordInExternallySharedRecord() async throws {
      let externalZoneID = CKRecordZone.ID(
        zoneName: "external.zone",
        ownerName: "external.owner"
      )

      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: UUID(1), zoneID: externalZoneID)
      )
      remindersListRecord.encryptedValues["id"] = UUID(1).uuidString.lowercased()
      remindersListRecord.encryptedValues["title"] = "Personal"
      remindersListRecord.userModificationDate = Date(timeIntervalSince1970: 1_234_567_890)
      let reminderRecord = CKRecord(
        recordType: Reminder.tableName,
        recordID: Reminder.recordID(for: UUID(1), zoneID: externalZoneID)
      )
      reminderRecord.encryptedValues["id"] = UUID(1).uuidString.lowercased()
      reminderRecord.encryptedValues["isCompleted"] = false
      reminderRecord.encryptedValues["title"] = "Get milk"
      reminderRecord.encryptedValues["remindersListID"] = UUID(1).uuidString.lowercased()
      remindersListRecord.userModificationDate = Date(timeIntervalSince1970: 1_234_567_890)
      await syncEngine.handleFetchedRecordZoneChanges(
        modifications: [
          remindersListRecord,
          reminderRecord
        ],
        syncEngine: syncEngine.private
      )

      try await database.asyncWrite { db in
        try Reminder.find(UUID(1)).delete().execute(db)
      }

      let batch = await syncEngine.nextRecordZoneChangeBatch(
        options: CKSyncEngine.SendChangesOptions(
          scope: .recordIDs([Reminder.recordID(for: UUID(1), zoneID: externalZoneID)])
        ),
        syncEngine: syncEngine.shared
      )
      assertInlineSnapshot(of: batch, as: .customDump) {
        """
        CKSyncEngine.RecordZoneChangeBatch(
          atomicByZone: false,
          recordIDsToDelete: [
            [0]: CKRecordID(
              recordName: "00000000-0000-0000-0000-000000000001:reminders",
              zoneID: CKRecordZoneID(
                zoneName: "external.zone",
                ownerName: "external.owner"
              )
            )
          ],
          recordsToSave: []
        )
        """
      }
    }
  }
}

// TODO: Assert on Metadata.parentRecordName when create new reminders in a shared list

@Table private struct NonSyncedTable {
  let id: UUID
}
