import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
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
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1))),
        .saveRecord(CKRecord.ID(UUID(1))),
        .saveRecord(CKRecord.ID(UUID(2))),
        .saveRecord(CKRecord.ID(UUID(3))),
      ])
      try database.write { db in
        try RemindersList.find(UUID(1)).delete().execute(db)
      }
      try database.read { db in
        try #expect(Reminder.all.fetchAll(db) == [])
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .deleteRecord(CKRecord.ID(UUID(1))),
        .deleteRecord(CKRecord.ID(UUID(1))),
        .deleteRecord(CKRecord.ID(UUID(2))),
        .deleteRecord(CKRecord.ID(UUID(3))),
      ])
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteSetNull() throws {
      try database.write { db in
        try db.seed {
          User(id: UUID(1), name: "Blob")
          RemindersList(id: UUID(2), title: "Personal")
          Reminder(
            id: UUID(3),
            assignedUserID: UUID(1),
            title: "Groceries",
            remindersListID: UUID(2)
          )
        }
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1))),
        .saveRecord(CKRecord.ID(UUID(2))),
        .saveRecord(CKRecord.ID(UUID(3))),
      ])
      try database.write { db in
        try User.find(UUID(1)).delete().execute(db)
      }
      try database.read { db in
        try expectNoDifference(
          Reminder.all.fetchAll(db),
          [
            Reminder(id: UUID(3), assignedUserID: nil, title: "Groceries", remindersListID: UUID(2)),
          ]
        )
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .deleteRecord(CKRecord.ID(UUID(1))),
        .saveRecord(CKRecord.ID(UUID(3))),
      ])
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func updateCascade() throws {
      try database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(1), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(2), title: "Walk", remindersListID: UUID(1))
          Reminder(id: UUID(3), title: "Haircut", remindersListID: UUID(1))
        }
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1))),
        .saveRecord(CKRecord.ID(UUID(1))),
        .saveRecord(CKRecord.ID(UUID(2))),
        .saveRecord(CKRecord.ID(UUID(3))),
      ])
      let newID = try database.write { db in
        try RemindersList.find(UUID(1)).update { $0.id = UUID() }.returning(\.id).fetchOne(db)!
      }
      try database.read { db in
        try expectNoDifference(
          Reminder.all.fetchAll(db),
          [
            Reminder(id: UUID(1), title: "Groceries", remindersListID: newID),
            Reminder(id: UUID(2), title: "Walk", remindersListID: newID),
            Reminder(id: UUID(3), title: "Haircut", remindersListID: newID)
          ]
        )
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(newID)),
        .saveRecord(CKRecord.ID(UUID(1))),
        .saveRecord(CKRecord.ID(UUID(2))),
        .saveRecord(CKRecord.ID(UUID(3))),
      ])
    }
  }
}
