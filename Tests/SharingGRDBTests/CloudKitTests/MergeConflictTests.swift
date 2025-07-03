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
  @Suite(.printTimestamps)
  final class MergeConflictTests: BaseCloudKitTests, @unchecked Sendable {
    @Dependency(\.date.now) var now

    @Test func merge_clientRecordUpdatedBeforeServerRecord() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "")
          Reminder(id: UUID(1), title: "", remindersListID: UUID(1))
        }
      }
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
                title: "",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_id: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_isCompleted: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_remindersListID: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_title: Date(2009-02-13T23:31:30.000Z)
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                title: "",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_id: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_title: Date(2009-02-13T23:31:30.000Z)
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

      let record = try syncEngine.private.database.record(for: Reminder.recordID(for: UUID(1)))
      let userModificationDate = now.addingTimeInterval(60)
      record.setValue("Buy milk", forKey: "title", at: userModificationDate)
      record.userModificationDate = userModificationDate
      _ = syncEngine.private.database.modifyRecords(saving: [record])

      try await withDependencies {
        $0.date.now = now.addingTimeInterval(30)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(UUID(1)).update { $0.isCompleted = true }.execute(db)
        }
      }
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
                title: "Buy milk",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:32:30.000Z),
                sqlitedata_icloud_userModificationDate_id: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_isCompleted: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_remindersListID: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_title: Date(2009-02-13T23:32:30.000Z)
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                title: "",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_id: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_title: Date(2009-02-13T23:31:30.000Z)
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
                isCompleted: 1,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                title: "Buy milk",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:32:30.000Z),
                sqlitedata_icloud_userModificationDate_id: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_isCompleted: Date(2009-02-13T23:32:00.000Z),
                sqlitedata_icloud_userModificationDate_remindersListID: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_title: Date(2009-02-13T23:32:30.000Z)
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                title: "",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_id: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_title: Date(2009-02-13T23:31:30.000Z)
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
    }

    @Test func serverRecordUpdatedBeforeClientRecord() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "")
          Reminder(id: UUID(1), title: "", remindersListID: UUID(1))
        }
      }
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
                title: "",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_id: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_isCompleted: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_remindersListID: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_title: Date(2009-02-13T23:31:30.000Z)
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                title: "",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_id: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_title: Date(2009-02-13T23:31:30.000Z)
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

      let record = try syncEngine.private.database.record(for: Reminder.recordID(for: UUID(1)))
      let userModificationDate = now.addingTimeInterval(30)
      record.setValue("Buy milk", forKey: "title", at: userModificationDate)
      record.userModificationDate = userModificationDate
      _ = syncEngine.private.database.modifyRecords(saving: [record])

      try await withDependencies {
        $0.date.now = now.addingTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(UUID(1)).update { $0.isCompleted = true }.execute(db)
        }
      }
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
                title: "Buy milk",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:32:00.000Z),
                sqlitedata_icloud_userModificationDate_id: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_isCompleted: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_remindersListID: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_title: Date(2009-02-13T23:32:00.000Z)
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                title: "",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_id: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_title: Date(2009-02-13T23:31:30.000Z)
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
                isCompleted: 1,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                title: "Buy milk",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:32:30.000Z),
                sqlitedata_icloud_userModificationDate_id: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_isCompleted: Date(2009-02-13T23:32:30.000Z),
                sqlitedata_icloud_userModificationDate_remindersListID: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_title: Date(2009-02-13T23:32:00.000Z)
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                title: "",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_id: Date(2009-02-13T23:31:30.000Z),
                sqlitedata_icloud_userModificationDate_title: Date(2009-02-13T23:31:30.000Z)
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
    }
  }
}
