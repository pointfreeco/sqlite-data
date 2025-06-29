import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class SetUpTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func schemaChange() async throws {
      let personalList = RemindersList(id: UUID(1), title: "Personal")
      let businessList = RemindersList(id: UUID(2), title: "Business")
      let reminder = Reminder(id: UUID(1), title: "Get milk", remindersListID: UUID(1))
      try await database.asyncWrite { db in
        try db.seed {
          personalList
          businessList
          reminder
        }
      }
      _ = await syncEngine.nextRecordZoneChangeBatch(syncEngine: syncEngine.private)

      let personalListRecord = try syncEngine.private.database.record(
        for: RemindersList.recordID(for: UUID(1))
      )
      personalListRecord.userModificationDate = Date()
      personalListRecord.encryptedValues["position"] = 1

      let businessListRecord = try syncEngine.private.database.record(
        for: RemindersList.recordID(for: UUID(2))
      )
      businessListRecord.userModificationDate = Date()
      businessListRecord.encryptedValues["position"] = 2

      let reminderRecord = try syncEngine.private.database.record(
        for: Reminder.recordID(for: UUID(1))
      )
      reminderRecord.userModificationDate = Date()
      reminderRecord.encryptedValues["position"] = 3

      _ = syncEngine.private.database.modifyRecords(
        saving: [personalListRecord, businessListRecord, reminderRecord],
        deleting: [],
        savePolicy: .ifServerRecordUnchanged,
        atomically: true
      )

      try await database.asyncWrite { db in
        try #sql(
          """
          ALTER TABLE "remindersLists" 
          ADD COLUMN "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
          """
        )
        .execute(db)
        try #sql(
          """
          ALTER TABLE "reminders" 
          ADD COLUMN "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
          """
        )
        .execute(db)
      }

      try await syncEngine.setUpSyncEngine()
      let batch = await syncEngine.nextRecordZoneChangeBatch(syncEngine: syncEngine.private)
      #expect(batch == nil)

      let remindersLists = try await database.read { db in
        try MigratedRemindersList.order(by: \.id).fetchAll(db)
      }
      let reminders = try await database.read { db in
        try MigratedReminder.order(by: \.id).fetchAll(db)
      }
      expectNoDifference(
        remindersLists,
        [
          MigratedRemindersList(id: UUID(1), title: "Personal", position: 1),
          MigratedRemindersList(id: UUID(2), title: "Business", position: 2),
        ]
      )
      expectNoDifference(
        reminders,
        [
          MigratedReminder(id: UUID(1), title: "Get milk", position: 3, remindersListID: UUID(1)),
        ]
      )
    }
  }
}

@Table("remindersLists")
fileprivate struct MigratedRemindersList: Equatable, Identifiable {
  let id: UUID
  var title = ""
  var position = 0
}

@Table("reminders")
fileprivate struct MigratedReminder: Equatable, Identifiable {
  let id: UUID
  var title = ""
  var position = 0
  var remindersListID: RemindersList.ID
}
