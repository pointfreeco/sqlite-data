#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import Foundation
  import InlineSnapshotTesting
  import SQLiteData
  import SQLiteDataTestSupport
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class UnsyncedRecordTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func receiveChildWithoutParent_ReceiveUpdatedChildWithoutParent() async throws {
        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1)
        )
        remindersListRecord.setValue(1, forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)

        let reminderRecord = CKRecord(
          recordType: Reminder.tableName,
          recordID: Reminder.recordID(for: 1)
        )
        reminderRecord.setValue(1, forKey: "id", at: now)
        reminderRecord.setValue("Get milk", forKey: "title", at: now)
        reminderRecord.setValue(1, forKey: "remindersListID", at: now)
        reminderRecord.parent = CKRecord.Reference(
          record: remindersListRecord,
          action: .none
        )

        let remindersListModification = try syncEngine.modifyRecords(
          scope: .private,
          saving: [remindersListRecord]
        )
        try await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord]).notify()

        assertQuery(
          UnsyncedRecordID.select { ($0.recordName, $0.record) },
          database: syncEngine.metadatabase
        ) {
          """
          ┌───────────────┬───────────────────────────────────────────────────────────────────────────────────────┐
          │ "1:reminders" │ CKRecord(                                                                             │
          │               │   recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),                           │
          │               │   recordType: "reminders",                                                            │
          │               │   parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)), │
          │               │   share: nil,                                                                         │
          │               │   id: 1,                                                                              │
          │               │   remindersListID: 1,                                                                 │
          │               │   title: "Get milk"                                                                   │
          │               │ )                                                                                     │
          └───────────────┴───────────────────────────────────────────────────────────────────────────────────────┘
          """
        }

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          let updatedReminderRecord = try syncEngine.private.database.record(
            for: Reminder.recordID(for: 1)
          )
          updatedReminderRecord.setValue("Buy milk", forKey: "title", at: now)
          try await syncEngine.modifyRecords(scope: .private, saving: [updatedReminderRecord])
            .notify()
        }

        assertQuery(Reminder.all, database: userDatabase.database) {
          """
          (No results)
          """
        }
        assertQuery(
          UnsyncedRecordID.select { ($0.recordName, $0.record) },
          database: syncEngine.metadatabase
        ) {
          """
          ┌───────────────┬───────────────────────────────────────────────────────────────────────────────────────┐
          │ "1:reminders" │ CKRecord(                                                                             │
          │               │   recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),                           │
          │               │   recordType: "reminders",                                                            │
          │               │   parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)), │
          │               │   share: nil,                                                                         │
          │               │   id: 1,                                                                              │
          │               │   remindersListID: 1,                                                                 │
          │               │   title: "Buy milk"                                                                   │
          │               │ )                                                                                     │
          └───────────────┴───────────────────────────────────────────────────────────────────────────────────────┘
          """
        }

        await remindersListModification.notify()

        assertQuery(Reminder.all, database: userDatabase.database) {
          """
          ┌───────────────────────┐
          │ Reminder(             │
          │   id: 1,              │
          │   dueDate: nil,       │
          │   isCompleted: false, │
          │   priority: nil,      │
          │   title: "Buy milk",  │
          │   remindersListID: 1  │
          │ )                     │
          └───────────────────────┘
          """
        }
        assertQuery(UnsyncedRecordID.all, database: syncEngine.metadatabase) {
          """
          (No results)
          """
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func cachedUnsyncedRecordsAreNotFetched() async throws {
        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1)
        )
        remindersListRecord.setValue(1, forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)

        let otherRemindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 2)
        )
        otherRemindersListRecord.setValue(2, forKey: "id", at: now)
        otherRemindersListRecord.setValue("Business", forKey: "title", at: now)

        let reminderRecord = CKRecord(
          recordType: Reminder.tableName,
          recordID: Reminder.recordID(for: 1)
        )
        reminderRecord.setValue(1, forKey: "id", at: now)
        reminderRecord.setValue("Get milk", forKey: "title", at: now)
        reminderRecord.setValue(1, forKey: "remindersListID", at: now)
        reminderRecord.parent = CKRecord.Reference(
          record: remindersListRecord,
          action: .none
        )

        let remindersListModification = try syncEngine.modifyRecords(
          scope: .private,
          saving: [remindersListRecord]
        )
        try await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord]).notify()
        try await syncEngine.modifyRecords(scope: .private, saving: [otherRemindersListRecord])
          .notify()

        assertQuery(Reminder.all, database: userDatabase.database) {
          """
          (No results)
          """
        }
        assertQuery(
          UnsyncedRecordID.select(\.recordName),
          database: syncEngine.metadatabase
        ) {
          """
          ┌───────────────┐
          │ "1:reminders" │
          └───────────────┘
          """
        }

        await remindersListModification.notify()

        assertQuery(Reminder.all, database: userDatabase.database) {
          """
          ┌───────────────────────┐
          │ Reminder(             │
          │   id: 1,              │
          │   dueDate: nil,       │
          │   isCompleted: false, │
          │   priority: nil,      │
          │   title: "Get milk",  │
          │   remindersListID: 1  │
          │ )                     │
          └───────────────────────┘
          """
        }
        assertQuery(UnsyncedRecordID.all, database: syncEngine.metadatabase) {
          """
          (No results)
          """
        }
        expectNoDifference(syncEngine.private.database.state.fetchedRecordIDs, [])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func uncachedUnsyncedRecordIDsAreFetched() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let reminderRecord = CKRecord(
          recordType: Reminder.tableName,
          recordID: Reminder.recordID(for: 1)
        )
        reminderRecord.setValue(1, forKey: "id", at: now)
        reminderRecord.setValue("Get milk", forKey: "title", at: now)
        reminderRecord.setValue(1, forKey: "remindersListID", at: now)
        reminderRecord.parent = CKRecord.Reference(
          recordID: RemindersList.recordID(for: 1),
          action: .none
        )
        _ = try syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])
        try await syncEngine.metadatabase.write { db in
          try UnsyncedRecordID.insert {
            UnsyncedRecordID(recordID: Reminder.recordID(for: 1))
          }
          .execute(db)
        }

        await syncEngine.handleEvent(
          .fetchedRecordZoneChanges(modifications: [], deletions: []),
          syncEngine: syncEngine.private
        )

        assertQuery(Reminder.all, database: userDatabase.database) {
          """
          ┌───────────────────────┐
          │ Reminder(             │
          │   id: 1,              │
          │   dueDate: nil,       │
          │   isCompleted: false, │
          │   priority: nil,      │
          │   title: "Get milk",  │
          │   remindersListID: 1  │
          │ )                     │
          └───────────────────────┘
          """
        }
        assertQuery(UnsyncedRecordID.all, database: syncEngine.metadatabase) {
          """
          (No results)
          """
        }
        expectNoDifference(
          syncEngine.private.database.state.fetchedRecordIDs,
          [Reminder.recordID(for: 1)]
        )
      }
    }
  }
#endif
