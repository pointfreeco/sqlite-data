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
        .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self)),
        .saveRecord(CKRecord.ID(UUID(1), in: Reminder.self)),
        .saveRecord(CKRecord.ID(UUID(2), in: Reminder.self)),
        .saveRecord(CKRecord.ID(UUID(3), in: Reminder.self)),
      ])
      try database.write { db in
        try RemindersList.find(UUID(1)).delete().execute(db)
      }
      try database.read { db in
        try #expect(Reminder.all.fetchAll(db) == [])
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .deleteRecord(CKRecord.ID(UUID(1), in: RemindersList.self)),
        .deleteRecord(CKRecord.ID(UUID(1), in: Reminder.self)),
        .deleteRecord(CKRecord.ID(UUID(2), in: Reminder.self)),
        .deleteRecord(CKRecord.ID(UUID(3), in: Reminder.self)),
      ])
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteSetNull() throws {
      try database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(1), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(2), title: "Dairy", parentReminderID: UUID(1), remindersListID: UUID(1))
          Reminder(id: UUID(3), title: "Milk", parentReminderID: UUID(2), remindersListID: UUID(1))
        }
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self)),
        .saveRecord(CKRecord.ID(UUID(1), in: Reminder.self)),
        .saveRecord(CKRecord.ID(UUID(2), in: Reminder.self)),
        .saveRecord(CKRecord.ID(UUID(3), in: Reminder.self)),
      ])
      try database.write { db in
        try Reminder.find(UUID(1)).delete().execute(db)
      }
      try database.read { db in
        try expectNoDifference(
          Reminder.all.fetchAll(db),
          [
            Reminder(id: UUID(2), title: "Dairy", parentReminderID: nil, remindersListID: UUID(1)),
            Reminder(id: UUID(3), title: "Milk", parentReminderID: UUID(2), remindersListID: UUID(1)),
          ]
        )
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .deleteRecord(CKRecord.ID(UUID(1), in: Reminder.self)),
        .saveRecord(CKRecord.ID(UUID(2), in: Reminder.self)),
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
        .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self)),
        .saveRecord(CKRecord.ID(UUID(1), in: Reminder.self)),
        .saveRecord(CKRecord.ID(UUID(2), in: Reminder.self)),
        .saveRecord(CKRecord.ID(UUID(3), in: Reminder.self)),
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
        .saveRecord(CKRecord.ID(newID, in: RemindersList.self)),
        .saveRecord(CKRecord.ID(UUID(1), in: Reminder.self)),
        .saveRecord(CKRecord.ID(UUID(2), in: Reminder.self)),
        .saveRecord(CKRecord.ID(UUID(3), in: Reminder.self)),
      ])
    }
  }
}
