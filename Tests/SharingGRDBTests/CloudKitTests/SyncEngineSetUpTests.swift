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
    @Dependency(\.date.now) var now

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func schemaChange() async throws {
      let personalList = RemindersList(id: UUID(1), title: "Personal")
      let businessList = RemindersList(id: UUID(2), title: "Business")
      let reminder = Reminder(id: UUID(1), title: "Get milk", remindersListID: UUID(1))
      try await userDatabase.userWrite { db in
        try db.seed {
          personalList
          businessList
          reminder
        }
      }

      await syncEngine.processBatch()

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        let personalListRecord = try syncEngine.private.database.record(
          for: RemindersList.recordID(for: UUID(1))
        )
        personalListRecord.setValue(1, forKey: "position", at: now)
        
        let businessListRecord = try syncEngine.private.database.record(
          for: RemindersList.recordID(for: UUID(2))
        )
        businessListRecord.setValue(2, forKey: "position", at: now)
        
        let reminderRecord = try syncEngine.private.database.record(
          for: Reminder.recordID(for: UUID(1))
        )
        reminderRecord.setValue(3, forKey: "position", at: now)
        
        await syncEngine.modifyRecords(
          scope: .private,
          saving: [personalListRecord, businessListRecord, reminderRecord]
        )

        try await userDatabase.userWrite { db in
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
        
        let relaunchedSyncEngine = try await SyncEngine(
          container: syncEngine.container,
          userDatabase: self.userDatabase,
          metadatabaseURL: URL
            .metadatabase(containerIdentifier: syncEngine.container.containerIdentifier!),
          tables: [
            MigratedReminder.self,
            MigratedRemindersList.self,
            Tag.self,
            ReminderTag.self,
            Parent.self,
            ChildWithOnDeleteRestrict.self,
            ChildWithOnDeleteSetNull.self,
            ChildWithOnDeleteSetDefault.self,
          ],
          privateTables: [
            RemindersListPrivate.self
          ]
        )
        
        await relaunchedSyncEngine.processBatch()
        
        let remindersLists = try await userDatabase.userRead { db in
          try MigratedRemindersList.order(by: \.id).fetchAll(db)
        }
        let reminders = try await userDatabase.userRead { db in
          try MigratedReminder.order(by: \.id).fetchAll(db)
        }
        withKnownIssue("This will be fixed once we properly update user database with last fetched record when schema changes") {
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
