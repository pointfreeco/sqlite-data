import CloudKit
import ConcurrencyExtras
import CustomDump
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class ReferenceViolationTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test(
      """
      * The local client moves a reminder to a list.
      * The remote client deletes that list.
      """
    ) func moveReminderToList_RemoteDeletesList() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          RemindersList(id: 2, title: "Business")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
        }
      }
      await syncEngine.processBatch()

      let modifications = {
        syncEngine.modifyRecords(scope: .private, deleting: [RemindersList.recordID(for: 2)])
      }()
      try withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.remindersListID = 2 }.execute(db)
        }
      }

      await syncEngine.processBatch()
      await modifications()
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
                parent: CKReference(recordID: CKRecord.ID(2:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: 1,
                isCompleted: 0,
                remindersListID: 2,
                title: "Get milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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

      try {
        try userDatabase.read { db in
          try #expect(Reminder.count().fetchOne(db) == 0)
          try #expect(
            RemindersList.all.fetchAll(db) == [
              RemindersList(id: 1, title: "Personal")
            ]
          )
        }
      }()
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test(
      """
      * The local client deletes a list.
      * The remote client adds reminder to that list.
      """
    ) func deleteList_RemoteAddsReminderToList() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
        }
      }
      await syncEngine.processBatch()

      try withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try userDatabase.userWrite { db in
          try RemindersList.find(1).delete().execute(db)
        }
      }
      let modifications = withDependencies {
        $0.date.now.addTimeInterval(2)
      } operation: {
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
        return {
          syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])
        }()
      }
      await syncEngine.processBatch()
      await modifications()
      await syncEngine.processBatch()
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
                id: 1,
                remindersListID: 1,
                title: "Get milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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

      try {
        try userDatabase.read { db in
          try #expect(
            Reminder.all.fetchAll(db) == [Reminder(id: 1, title: "Get milk", remindersListID: 1)]
          )
          try #expect(
            RemindersList.all.fetchAll(db) == [RemindersList(id: 1, title: "Personal")]
          )
        }
      }()
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test(
      """
      * The local client deletes a list.
      * The remote client adds reminder to that list.
      * Remote syncs to local client before local sends batch.
      """
    ) func deleteList_RemoteAddsReminderToList_Variation() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
        }
      }
      await syncEngine.processBatch()

      try withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try userDatabase.userWrite { db in
          try RemindersList.find(1).delete().execute(db)
        }
      }
      let modifications = withDependencies {
        $0.date.now.addTimeInterval(2)
      } operation: {
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
        return {
          syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])
        }()
      }
      await modifications()
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
                id: 1,
                remindersListID: 1,
                title: "Get milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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

      try {
        try userDatabase.read { db in
          try #expect(
            Reminder.all.fetchAll(db) == [Reminder(id: 1, title: "Get milk", remindersListID: 1)]
          )
          try #expect(
            RemindersList.all.fetchAll(db) == [RemindersList(id: 1, title: "Personal")]
          )
        }
      }()
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test(
      """
      * The local client moves child to parent.
      * The remote client deletes parent.
      * Local client sets parent relationship to NULL.
      """
    ) func moveChildToParent_RemoteDeletesParent_CascadeSetNull() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          Parent(id: 1)
          Parent(id: 2)
          ChildWithOnDeleteSetNull(id: 1, parentID: 1)
        }
      }
      await syncEngine.processBatch()

      let modifications = {
        syncEngine.modifyRecords(scope: .private, deleting: [Parent.recordID(for: 2)])
      }()
      try withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try userDatabase.userWrite { db in
          try ChildWithOnDeleteSetNull.find(1).update { $0.parentID = 2 }.execute(db)
        }
      }
      try await withDependencies {
        $0.date.now.addTimeInterval(2)
      } operation: {
        await syncEngine.processBatch()
        await modifications()
        await syncEngine.processBatch()

        assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:childWithOnDeleteSetNulls/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                  recordType: "childWithOnDeleteSetNulls",
                  parent: CKReference(recordID: CKRecord.ID(2:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                  share: nil,
                  id: 1,
                  parentID: 2
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                  recordType: "parents",
                  parent: nil,
                  share: nil,
                  id: 1
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
        try {
          try userDatabase.read { db in
            try #expect(
              ChildWithOnDeleteSetNull.all.fetchAll(db) == [
                ChildWithOnDeleteSetNull(id: 1, parentID: nil)
              ]
            )
            try #expect(
              Parent.all.fetchAll(db) == [
                Parent(id: 1)
              ]
            )
          }
        }()
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test(
      """
      * The local client moves child to parent.
      * The remote client deletes parent.
      * Local client sets parent relationship to default value.
      """
    ) func moveChildToParent_RemoteDeletesParent_CascadeSetDefault() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          Parent(id: 0)
          Parent(id: 1)
          Parent(id: 2)
          ChildWithOnDeleteSetDefault(id: 1, parentID: 1)
        }
      }
      await syncEngine.processBatch()

      let modifications = {
        syncEngine.modifyRecords(scope: .private, deleting: [Parent.recordID(for: 2)])
      }()
      try withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try userDatabase.userWrite { db in
          try ChildWithOnDeleteSetDefault.find(1).update { $0.parentID = 2 }.execute(db)
        }
      }
      try await withDependencies {
        $0.date.now.addTimeInterval(2)
      } operation: {
        await syncEngine.processBatch()
        await modifications()
        await syncEngine.processBatch()

        assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:childWithOnDeleteSetDefaults/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                  recordType: "childWithOnDeleteSetDefaults",
                  parent: CKReference(recordID: CKRecord.ID(2:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                  share: nil,
                  id: 1,
                  parentID: 2
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(0:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                  recordType: "parents",
                  parent: nil,
                  share: nil,
                  id: 0
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                  recordType: "parents",
                  parent: nil,
                  share: nil,
                  id: 1
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
        try {
          try userDatabase.read { db in
            try #expect(
              ChildWithOnDeleteSetDefault.all.fetchAll(db) == [
                ChildWithOnDeleteSetDefault(id: 1, parentID: 0)
              ]
            )
            try #expect(
              Parent.all.fetchAll(db) == [Parent(id: 0), Parent(id: 1)]
            )
          }
        }()
      }
    }
  }
}
