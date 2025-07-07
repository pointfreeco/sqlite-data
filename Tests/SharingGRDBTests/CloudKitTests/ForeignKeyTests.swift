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
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(1), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(2), title: "Walk", remindersListID: UUID(1))
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
                title: "Groceries"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(2:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000002",
                isCompleted: 0,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                title: "Walk"
              ),
              [2]: CKRecord(
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

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try RemindersList.find(UUID(1)).delete().execute(db)
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
          Parent(id: UUID(1))
          ChildWithOnDeleteSetNull(id: UUID(1), parentID: UUID(1))
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
                id: "00000000-0000-0000-0000-000000000001",
                parentID: "00000000-0000-0000-0000-000000000001"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "parents",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001"
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
          try Parent.find(UUID(1)).delete().execute(db)
        }
      }
      try await userDatabase.userRead { db in
        try expectNoDifference(
          ChildWithOnDeleteSetNull.all.fetchAll(db),
          [
            ChildWithOnDeleteSetNull(id: UUID(1), parentID: nil)
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
                id: "00000000-0000-0000-0000-000000000001"
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
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(2), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(3), title: "Walk", remindersListID: UUID(1))
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
                id: "00000000-0000-0000-0000-000000000002",
                isCompleted: 0,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                title: "Groceries"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(3:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000003",
                isCompleted: 0,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                title: "Walk"
              ),
              [2]: CKRecord(
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

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try RemindersList.find(UUID(1)).update { $0.id = UUID(9) }.execute(db)
        }
      }
      try await userDatabase.userRead { db in
        try expectNoDifference(
          Reminder.all.fetchAll(db),
          [
            Reminder(id: UUID(2), title: "Groceries", remindersListID: UUID(9)),
            Reminder(id: UUID(3), title: "Walk", remindersListID: UUID(9)),
            Reminder(id: UUID(4), title: "Haircut", remindersListID: UUID(9)),
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
                id: "00000000-0000-0000-0000-000000000002",
                isCompleted: 0,
                remindersListID: "00000000-0000-0000-0000-000000000009",
                title: "Groceries"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(3:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(9:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000003",
                isCompleted: 0,
                remindersListID: "00000000-0000-0000-0000-000000000009",
                title: "Walk"
              ),
              [2]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal"
              ),
              [3]: CKRecord(
                recordID: CKRecord.ID(9:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000009",
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
    @Test func deleteRestrict() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          Parent(id: UUID(1))
          ChildWithOnDeleteRestrict(id: UUID(1), parentID: UUID(1))
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
                recordID: CKRecord.ID(1:childWithOnDeleteRestricts/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "childWithOnDeleteRestricts",
                parent: CKReference(recordID: CKRecord.ID(1:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                parentID: "00000000-0000-0000-0000-000000000001"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "parents",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001"
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
      let error = #expect(throws: DatabaseError.self) {
        try withDependencies {
          $0.date.now.addTimeInterval(60)
        } operation: {
          try self.userDatabase.userWrite { db in
            try Parent.find(UUID(1)).delete().execute(db)
          }
        }
      }
      #expect(try #require(error).localizedDescription.contains("FOREIGN KEY constraint failed"))
      try await userDatabase.userRead { db in
        try expectNoDifference(
          ChildWithOnDeleteRestrict.all.fetchAll(db),
          [
            ChildWithOnDeleteRestrict(id: UUID(1), parentID: UUID(1))
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
                recordID: CKRecord.ID(1:childWithOnDeleteRestricts/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "childWithOnDeleteRestricts",
                parent: CKReference(recordID: CKRecord.ID(1:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                parentID: "00000000-0000-0000-0000-000000000001"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "parents",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001"
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
    @Test func updateRestrict() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          Parent(id: UUID(1))
          ChildWithOnDeleteRestrict(id: UUID(1), parentID: UUID(1))
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
                recordID: CKRecord.ID(1:childWithOnDeleteRestricts/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "childWithOnDeleteRestricts",
                parent: CKReference(recordID: CKRecord.ID(1:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                parentID: "00000000-0000-0000-0000-000000000001"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "parents",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001"
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
      let error = #expect(throws: DatabaseError.self) {
        try withDependencies {
          $0.date.now.addTimeInterval(60)
        } operation: {
          try self.userDatabase.userWrite { db in
            try Parent.find(UUID(1)).update { $0.id = UUID(2) }.execute(db)
          }
        }
      }
      #expect(try #require(error).localizedDescription.contains("FOREIGN KEY constraint failed"))
      try await userDatabase.userRead { db in
        try expectNoDifference(
          ChildWithOnDeleteRestrict.all.fetchAll(db),
          [
            ChildWithOnDeleteRestrict(id: UUID(1), parentID: UUID(1))
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
                recordID: CKRecord.ID(1:childWithOnDeleteRestricts/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "childWithOnDeleteRestricts",
                parent: CKReference(recordID: CKRecord.ID(1:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                parentID: "00000000-0000-0000-0000-000000000001"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:parents/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "parents",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001"
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
          LocalUser(id: UUID(1), name: "Blob", parentID: nil)
          LocalUser(id: UUID(2), name: "Blob Jr", parentID: UUID(1))
        }
      }
      try await self.userDatabase.userWrite { db in
        try LocalUser.find(UUID(1)).delete().execute(db)
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
