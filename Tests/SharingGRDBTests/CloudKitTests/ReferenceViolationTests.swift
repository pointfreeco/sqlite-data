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
                parent: nil,
                share: nil,
                id: 1
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
  }
}
