import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class ForeignKeyTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteCascade() throws {
      try database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(1), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(2), title: "Walk", remindersListID: UUID(1))
          Reminder(id: UUID(3), title: "Haircut", remindersListID: UUID(1))
        }
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1))),
        .saveRecord(Reminder.recordID(for: UUID(1))),
        .saveRecord(Reminder.recordID(for: UUID(2))),
        .saveRecord(Reminder.recordID(for: UUID(3))),
      ])
      try database.write { db in
        try RemindersList.find(UUID(1)).delete().execute(db)
      }
      try database.read { db in
        try #expect(Reminder.all.fetchAll(db) == [])
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .deleteRecord(RemindersList.recordID(for: UUID(1))),
        .deleteRecord(Reminder.recordID(for: UUID(1))),
        .deleteRecord(Reminder.recordID(for: UUID(2))),
        .deleteRecord(Reminder.recordID(for: UUID(3))),
      ])
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteSetNull() throws {
      try database.write { db in
        try db.seed {
          Parent(id: UUID(1))
          ChildWithOnDeleteSetNull(id: UUID(1), parentID: UUID(1))
        }
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(Parent.recordID(for: UUID(1))),
        .saveRecord(ChildWithOnDeleteSetNull.recordID(for: UUID(1))),
      ])
      try database.write { db in
        try Parent.find(UUID(1)).delete().execute(db)
      }
      try database.read { db in
        try expectNoDifference(
          ChildWithOnDeleteSetNull.all.fetchAll(db),
          [
            ChildWithOnDeleteSetNull(id: UUID(1), parentID: nil)
          ]
        )
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .deleteRecord(Parent.recordID(for: UUID(1))),
        .saveRecord(ChildWithOnDeleteSetNull.recordID(for: UUID(1))),
      ])
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func updateCascade() throws {
      try database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(2), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(3), title: "Walk", remindersListID: UUID(1))
          Reminder(id: UUID(4), title: "Haircut", remindersListID: UUID(1))
        }
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1))),
        .saveRecord(Reminder.recordID(for: UUID(2))),
        .saveRecord(Reminder.recordID(for: UUID(3))),
        .saveRecord(Reminder.recordID(for: UUID(4))),
      ])
      try database.write { db in
        try RemindersList.find(UUID(1)).update { $0.id = UUID(9) }.execute(db)
      }
      try database.read { db in
        try expectNoDifference(
          Reminder.all.fetchAll(db),
          [
            Reminder(id: UUID(2), title: "Groceries", remindersListID: UUID(9)),
            Reminder(id: UUID(3), title: "Walk", remindersListID: UUID(9)),
            Reminder(id: UUID(4), title: "Haircut", remindersListID: UUID(9)),
          ]
        )
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(9))),
        .saveRecord(Reminder.recordID(for: UUID(2))),
        .saveRecord(Reminder.recordID(for: UUID(3))),
        .saveRecord(Reminder.recordID(for: UUID(4))),
      ])
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteRestrict() throws {
      try database.write { db in
        try db.seed {
          Parent(id: UUID(1))
          ChildWithOnDeleteRestrict(id: UUID(1), parentID: UUID(1))
        }
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(Parent.recordID(for: UUID(1))),
        .saveRecord(ChildWithOnDeleteRestrict.recordID(for: UUID(1))),
      ])
      do {
        let error = #expect(throws: DatabaseError.self) {
          try self.database.write { db in
            try Parent.find(UUID(1)).delete().execute(db)
          }
        }
        #expect(try #require(error).localizedDescription.contains("FOREIGN KEY constraint failed"))
        try database.read { db in
          try expectNoDifference(
            ChildWithOnDeleteRestrict.all.fetchAll(db),
            [
              ChildWithOnDeleteRestrict(id: UUID(1), parentID: UUID(1))
            ]
          )
        }
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func updateRestrict() throws {
      try database.write { db in
        try db.seed {
          Parent(id: UUID(1))
          ChildWithOnDeleteRestrict(id: UUID(1), parentID: UUID(1))
        }
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(Parent.recordID(for: UUID(1))),
        .saveRecord(ChildWithOnDeleteRestrict.recordID(for: UUID(1))),
      ])

      let error = #expect(throws: DatabaseError.self) {
        try self.database.write { db in
          try Parent.find(UUID(1)).update { $0.id = UUID(2) }.execute(db)
        }
      }
      #expect(try #require(error).localizedDescription.contains("FOREIGN KEY constraint failed"))
      try database.read { db in
        try expectNoDifference(
          ChildWithOnDeleteRestrict.all.fetchAll(db),
          [
            ChildWithOnDeleteRestrict(id: UUID(1), parentID: UUID(1))
          ]
        )
      }
    }
  }
}
