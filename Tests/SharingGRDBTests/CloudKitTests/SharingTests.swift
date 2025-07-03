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
    @Dependency(\.date.now) var now

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareNonRootRecord() async throws {
      let reminder = Reminder(id: UUID(1), title: "Groceries", remindersListID: UUID(1))
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          reminder
        }
      }

      await syncEngine.processBatch()

      await #expect(throws: SyncEngine.RecordMustBeRoot.self) {
        _ = try await self.syncEngine.share(record: reminder, configure: { _ in })
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
      remindersListRecord.setValue(UUID(1).uuidString.lowercased(), forKey: "id", at: now)
      remindersListRecord.setValue(false, forKey: "isCompleted", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)
      remindersListRecord.userModificationDate = now

      await syncEngine.modifyRecords(scope: .shared, saving: [remindersListRecord])

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try db.seed {
            Reminder(id: UUID(1), title: "Get milk", remindersListID: UUID(1))
          }
        }
      }

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
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/external.zone/external.owner),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                isCompleted: 0,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                title: "Get milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                isCompleted: 0,
                title: "Personal"
              )
            ]
          )
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
      remindersListRecord.setValue(UUID(1).uuidString.lowercased(), forKey: "id", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)
      remindersListRecord.userModificationDate = now
      let reminderRecord = CKRecord(
        recordType: Reminder.tableName,
        recordID: Reminder.recordID(for: UUID(1), zoneID: externalZoneID)
      )
      reminderRecord.setValue(UUID(1).uuidString.lowercased(), forKey: "id", at: now)
      reminderRecord.setValue(false, forKey: "isCompleted", at: now)
      reminderRecord.setValue("Get milk", forKey: "title", at: now)
      reminderRecord.setValue(UUID(1).uuidString.lowercased(), forKey: "remindersListID", at: now)
      remindersListRecord.userModificationDate = now

      await syncEngine.modifyRecords(scope: .shared, saving: [remindersListRecord])

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(UUID(1)).delete().execute(db)
        }
      }

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
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal"
              )
            ]
          )
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
