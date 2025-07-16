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
  final class ForeignKeyTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteCascade() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, title: "Groceries", remindersListID: 1)
          Reminder(id: 2, title: "Walk", remindersListID: 1)
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
                id: 1,
                isCompleted: 0,
                remindersListID: 1,
                title: "Groceries"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(2:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: 2,
                isCompleted: 0,
                remindersListID: 1,
                title: "Walk"
              ),
              [2]: CKRecord(
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

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try RemindersList.find(1).delete().execute(db)
        }
      }
      try await userDatabase.userRead { db in
        try #expect(Reminder.all.fetchAll(db) == [])
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
            storage: []
          )
        )
        """
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteSetNull() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          Parent(id: 1)
          ChildWithOnDeleteSetNull(id: 1, parentID: 1)
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
                recordID: CKRecord.ID(1:childWithOnDeleteSetNulls/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "childWithOnDeleteSetNulls",
                parent: CKReference(recordID: CKRecord.ID(1:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: 1,
                parentID: 1
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

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try Parent.find(1).delete().execute(db)
        }
      }
      try await userDatabase.userRead { db in
        try expectNoDifference(
          ChildWithOnDeleteSetNull.all.fetchAll(db),
          [
            ChildWithOnDeleteSetNull(id: 1, parentID: nil)
          ]
        )
      }

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

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func updateCascade() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 2, title: "Groceries", remindersListID: 1)
          Reminder(id: 3, title: "Walk", remindersListID: 1)
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
                recordID: CKRecord.ID(2:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: 2,
                isCompleted: 0,
                remindersListID: 1,
                title: "Groceries"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(3:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: 3,
                isCompleted: 0,
                remindersListID: 1,
                title: "Walk"
              ),
              [2]: CKRecord(
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

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try RemindersList.find(1).update { $0.id = 9 }.execute(db)
        }
      }
      try await userDatabase.userRead { db in
        try expectNoDifference(
          Reminder.all.fetchAll(db),
          [
            Reminder(id: 2, title: "Groceries", remindersListID: 9),
            Reminder(id: 3, title: "Walk", remindersListID: 9),
            Reminder(id: 4, title: "Haircut", remindersListID: 9),
          ]
        )
      }

      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(2:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(9:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: 2,
                isCompleted: 0,
                remindersListID: 9,
                title: "Groceries"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(3:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(9:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: 3,
                isCompleted: 0,
                remindersListID: 9,
                title: "Walk"
              ),
              [2]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                title: "Personal"
              ),
              [3]: CKRecord(
                recordID: CKRecord.ID(9:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 9,
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
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func nonSyncTable() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          LocalUser(id: 1, name: "Blob", parentID: nil)
          LocalUser(id: 2, name: "Blob Jr", parentID: 1)
        }
      }
      try await self.userDatabase.userWrite { db in
        try LocalUser.find(1).delete().execute(db)
      }
      try await userDatabase.userRead { db in
        try expectNoDifference(
          LocalUser.all.fetchAll(db),
          []
        )
      }
    }
  }
}
