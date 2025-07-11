import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class SchemaChangeTests: BaseCloudKitTests, @unchecked Sendable {
    @Dependency(\.date.now) var now
    @Dependency(\.dataManager) var dataManager
    var inMemoryDataManager: InMemoryDataManager {
      dataManager as! InMemoryDataManager
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func addColumnToRemindersAndRemindersLists() async throws {
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
          userDatabase: syncEngine.userDatabase,
          metadatabaseURL: URL(filePath: syncEngine.metadatabase.path),
          tables: syncEngine.tables,
          privateTables: syncEngine.privateTables
        )

        await relaunchedSyncEngine.processBatch()

        let remindersLists = try await userDatabase.userRead { db in
          try RemindersListWithPosition.order(by: \.id).fetchAll(db)
        }
        let reminders = try await userDatabase.userRead { db in
          try ReminderWithPosition.order(by: \.id).fetchAll(db)
        }

        expectNoDifference(
          remindersLists,
          [
            RemindersListWithPosition(id: UUID(1), title: "Personal", position: 1),
            RemindersListWithPosition(id: UUID(2), title: "Business", position: 2),
          ]
        )
        expectNoDifference(
          reminders,
          [
            ReminderWithPosition(
              id: UUID(1),
              title: "Get milk",
              position: 3,
              remindersListID: UUID(1)
            )
          ]
        )
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func addAssetToRemindersList() async throws {
      let personalList = RemindersList(id: UUID(1), title: "Personal")
      try await userDatabase.userWrite { db in
        try db.seed {
          personalList
        }
      }

      await syncEngine.processBatch()

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        let personalListRecord = try syncEngine.private.database.record(
          for: RemindersList.recordID(for: UUID(1))
        )
        personalListRecord.setValue(Array("image".utf8), forKey: "image", at: now)

        await syncEngine.modifyRecords(
          scope: .private,
          saving: [personalListRecord]
        )

        try await userDatabase.userWrite { db in
          try #sql(
            """
            ALTER TABLE "remindersLists" 
            ADD COLUMN "image" BLOB NOT NULL ON CONFLICT REPLACE DEFAULT X''
            """
          )
          .execute(db)
        }

        let relaunchedSyncEngine = try await SyncEngine(
          container: syncEngine.container,
          userDatabase: syncEngine.userDatabase,
          metadatabaseURL: URL(filePath: syncEngine.metadatabase.path),
          tables: syncEngine.tables,
          privateTables: syncEngine.privateTables
        )

        await relaunchedSyncEngine.processBatch()

        let remindersLists = try await userDatabase.userRead { db in
          try RemindersListWithData.order(by: \.id).fetchAll(db)
        }

        expectNoDifference(
          remindersLists,
          [
            RemindersListWithData(id: UUID(1), image: Data("image".utf8), title: "Personal")
          ]
        )
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func addAssetToRemindersList_RemovedFromStorage() async throws {
      let personalList = RemindersList(id: UUID(1), title: "Personal")
      try await userDatabase.userWrite { db in
        try db.seed {
          personalList
        }
      }

      await syncEngine.processBatch()

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        let personalListRecord = try syncEngine.private.database.record(
          for: RemindersList.recordID(for: UUID(1))
        )
        personalListRecord.setValue(Array("image".utf8), forKey: "image", at: now)

        await syncEngine.modifyRecords(
          scope: .private,
          saving: [personalListRecord]
        )

        inMemoryDataManager.storage.withValue { $0.removeAll() }

        try await userDatabase.userWrite { db in
          try #sql(
            """
            ALTER TABLE "remindersLists" 
            ADD COLUMN "image" BLOB NOT NULL ON CONFLICT REPLACE DEFAULT X''
            """
          )
          .execute(db)
        }

        await withKnownIssue("TODO: Handle assets that need to be re-downloaded") {
          let relaunchedSyncEngine = try await SyncEngine(
            container: syncEngine.container,
            userDatabase: syncEngine.userDatabase,
            metadatabaseURL: URL(filePath: syncEngine.metadatabase.path),
            tables: syncEngine.tables,
            privateTables: syncEngine.privateTables
          )

          await relaunchedSyncEngine.processBatch()

          let remindersLists = try await userDatabase.userRead { db in
            try RemindersListWithData.order(by: \.id).fetchAll(db)
          }

          expectNoDifference(
            remindersLists,
            [
              RemindersListWithData(id: UUID(1), image: Data("image".utf8), title: "Personal")
            ]
          )
        }
      }
    }
  }
}

@Table("remindersLists")
private struct RemindersListWithPosition: Equatable, Identifiable {
  let id: UUID
  var title = ""
  var position = 0
}

@Table("reminders")
private struct ReminderWithPosition: Equatable, Identifiable {
  let id: UUID
  var title = ""
  var position = 0
  var remindersListID: RemindersList.ID
}

@Table("remindersLists")
private struct RemindersListWithData: Equatable, Identifiable {
  let id: UUID
  var image: Data
  var title = ""
}
