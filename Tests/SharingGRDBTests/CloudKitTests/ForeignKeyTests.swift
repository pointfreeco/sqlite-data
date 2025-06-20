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
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(User.recordID(for: UUID(1))),
        .saveRecord(RemindersList.recordID(for: UUID(2))),
        .saveRecord(Reminder.recordID(for: UUID(3))),
      ])
      try database.write { db in
        try User.find(UUID(1)).delete().execute(db)
      }
      try database.read { db in
        try expectNoDifference(
          Reminder.all.fetchAll(db),
          [
            Reminder(id: UUID(3), assignedUserID: nil, title: "Groceries", remindersListID: UUID(2))
          ]
        )
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .deleteRecord(User.recordID(for: UUID(1))),
        .saveRecord(Reminder.recordID(for: UUID(3))),
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
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(2), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(3), title: "Milk", parentReminderID: UUID(2), remindersListID: UUID(1))
        }
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1))),
        .saveRecord(Reminder.recordID(for: UUID(2))),
        .saveRecord(Reminder.recordID(for: UUID(3))),
      ])
      do {
        let error = #expect(throws: DatabaseError.self) {
          try self.database.write { db in
            try Reminder.find(UUID(2)).delete().execute(db)
          }
        }
        #expect(try #require(error).localizedDescription.contains("FOREIGN KEY constraint failed"))
        try database.read { db in
          try expectNoDifference(
            Reminder.all.fetchAll(db),
            [
              Reminder(id: UUID(2), title: "Groceries", remindersListID: UUID(1)),
              Reminder(
                id: UUID(3),
                title: "Milk",
                parentReminderID: UUID(2),
                remindersListID: UUID(1)
              ),
            ]
          )
        }
      }

      do {
        let error = #expect(throws: DatabaseError.self) {
          try self.database.write { db in
            try RemindersList.find(UUID(1)).delete().execute(db)
          }
        }
        #expect(try #require(error).localizedDescription.contains("FOREIGN KEY constraint failed"))
        try database.read { db in
          try expectNoDifference(
            Reminder.all.fetchAll(db),
            [
              Reminder(id: UUID(2), title: "Groceries", remindersListID: UUID(1)),
              Reminder(
                id: UUID(3),
                title: "Milk",
                parentReminderID: UUID(2),
                remindersListID: UUID(1)
              ),
            ]
          )
        }
        try database.read { db in
          try expectNoDifference(
            RemindersList.all.fetchAll(db),
            [RemindersList(id: UUID(1), title: "Personal")]
          )
        }
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func updateRestrict() throws {
      try database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(2), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(3), title: "Milk", parentReminderID: UUID(2), remindersListID: UUID(1))
        }
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1))),
        .saveRecord(Reminder.recordID(for: UUID(2))),
        .saveRecord(Reminder.recordID(for: UUID(3))),
      ])

      let error = #expect(throws: DatabaseError.self) {
        try self.database.write { db in
          try Reminder.find(UUID(2)).update { $0.id = UUID(9) }.execute(db)
        }
      }
      #expect(try #require(error).localizedDescription.contains("FOREIGN KEY constraint failed"))
      try database.read { db in
        try expectNoDifference(
          Reminder.all.fetchAll(db),
          [
            Reminder(id: UUID(2), title: "Groceries", remindersListID: UUID(1)),
            Reminder(
              id: UUID(3),
              title: "Milk",
              parentReminderID: UUID(2),
              remindersListID: UUID(1)
            ),
          ]
        )
      }

      withKnownIssue("We would prefer that no '.savedRecord's are appended.") {
        // NB: A '.savedRecord(UUID(9))' is being enqueued.
        privateSyncEngine.state.assertPendingRecordZoneChanges([])
      }
    }
  }
}
