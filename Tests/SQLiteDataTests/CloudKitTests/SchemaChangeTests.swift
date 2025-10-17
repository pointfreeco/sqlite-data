#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import Foundation
  import InlineSnapshotTesting
  import SQLiteData
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    final class SchemaChangeTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func addColumnToRemindersAndRemindersLists() async throws {
        let personalList = RemindersList(id: 1, title: "Personal")
        let businessList = RemindersList(id: 2, title: "Business")
        let reminder = Reminder(id: 1, title: "Get milk", remindersListID: 1)
        try await userDatabase.userWrite { db in
          try db.seed {
            personalList
            businessList
            reminder
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 60
        } operation: {
          let personalListRecord = try syncEngine.private.database.record(
            for: RemindersList.recordID(for: 1)
          )
          personalListRecord.setValue(1, forKey: "position", at: now)

          let businessListRecord = try syncEngine.private.database.record(
            for: RemindersList.recordID(for: 2)
          )
          businessListRecord.setValue(2, forKey: "position", at: now)

          let reminderRecord = try syncEngine.private.database.record(
            for: Reminder.recordID(for: 1)
          )
          reminderRecord.setValue(3, forKey: "position", at: now)

          try await syncEngine.modifyRecords(
            scope: .private,
            saving: [personalListRecord, businessListRecord, reminderRecord]
          )
          .notify()

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
            tables: syncEngine.tables
              .filter { $0.base != Reminder.self && $0.base != RemindersList.self }
              + [
                SynchronizedTable(for: ReminderWithPosition.self),
                SynchronizedTable(for: RemindersListWithPosition.self),
              ],
            privateTables: syncEngine.privateTables
          )
          defer { _ = relaunchedSyncEngine }

          let remindersLists = try await userDatabase.read { db in
            try RemindersListWithPosition.order(by: \.id).fetchAll(db)
          }
          let reminders = try await userDatabase.read { db in
            try ReminderWithPosition.order(by: \.id).fetchAll(db)
          }

          expectNoDifference(
            remindersLists,
            [
              RemindersListWithPosition(id: 1, title: "Personal", position: 1),
              RemindersListWithPosition(id: 2, title: "Business", position: 2),
            ]
          )
          expectNoDifference(
            reminders,
            [
              ReminderWithPosition(
                id: 1,
                title: "Get milk",
                position: 3,
                remindersListID: 1
              )
            ]
          )
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func addAssetToRemindersList() async throws {
        let personalList = RemindersList(id: 1, title: "Personal")
        try await userDatabase.userWrite { db in
          try db.seed {
            personalList
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 60
        } operation: {
          let personalListRecord = try syncEngine.private.database.record(
            for: RemindersList.recordID(for: 1)
          )
          personalListRecord.setValue(Array("image".utf8), forKey: "image", at: now)

          try await syncEngine.modifyRecords(
            scope: .private,
            saving: [personalListRecord]
          )
          .notify()

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
            tables: syncEngine.tables
              .filter { $0.base != RemindersList.self }
              + [SynchronizedTable(for: RemindersListWithData.self)],
            privateTables: syncEngine.privateTables
          )
          defer { _ = relaunchedSyncEngine }

          let remindersLists = try await userDatabase.read { db in
            try RemindersListWithData.order(by: \.id).fetchAll(db)
          }

          expectNoDifference(
            remindersLists,
            [
              RemindersListWithData(id: 1, image: Data("image".utf8), title: "Personal")
            ]
          )
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func addAssetToRemindersList_Redownload() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersList(id: 2, title: "Business")
            RemindersList(id: 3, title: "Secret")
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 60
        } operation: {
          let personalListRecord = try syncEngine.private.database.record(
            for: RemindersList.recordID(for: 1)
          )
          personalListRecord.setValue(Array("personal-image".utf8), forKey: "image", at: now)
          let businessListRecord = try syncEngine.private.database.record(
            for: RemindersList.recordID(for: 2)
          )
          businessListRecord.setValue(Array("business-image".utf8), forKey: "image", at: now)
          let secretListRecord = try syncEngine.private.database.record(
            for: RemindersList.recordID(for: 3)
          )
          secretListRecord.setValue(Array("secret-image".utf8), forKey: "image", at: now)

          try await syncEngine.modifyRecords(
            scope: .private,
            saving: [personalListRecord, businessListRecord, secretListRecord]
          )
          .notify()

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

          let relaunchedSyncEngine = try await SyncEngine(
            container: syncEngine.container,
            userDatabase: syncEngine.userDatabase,
            tables: syncEngine.tables
              .filter { $0.base != RemindersList.self }
              + [SynchronizedTable(for: RemindersListWithData.self)],
            privateTables: syncEngine.privateTables
          )
          defer { _ = relaunchedSyncEngine }

          let remindersLists = try await userDatabase.read { db in
            try RemindersListWithData.order(by: \.id).fetchAll(db)
          }

          expectNoDifference(
            remindersLists,
            [
              RemindersListWithData(id: 1, image: Data("personal-image".utf8), title: "Personal"),
              RemindersListWithData(id: 2, image: Data("business-image".utf8), title: "Business"),
              RemindersListWithData(id: 3, image: Data("secret-image".utf8), title: "Secret"),
            ]
          )
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func newTable() async throws {
        try await withDependencies {
          $0.currentTime.now += 60
        } operation: {
          let imageRecord = CKRecord(
            recordType: "images",
            recordID: Image.recordID(for: 1)
          )
          imageRecord.setValue("1", forKey: "id", at: now)
          imageRecord.setValue("A good image", forKey: "caption", at: now)
          imageRecord.setValue(Data("image".utf8), forKey: "image", at: now)

          try await syncEngine.modifyRecords(
            scope: .private,
            saving: [imageRecord]
          )
          .notify()

          inMemoryDataManager.storage.withValue { $0.removeAll() }

          try await userDatabase.userWrite { db in
            try #sql(
              """
              CREATE TABLE "images" (
                "id" TEXT NOT NULL PRIMARY KEY ON CONFLICT REPLACE DEFAULT (uuid()),
                "caption" TEXT NOT NULL,
                "image" BLOB NOT NULL
              )
              """
            )
            .execute(db)
          }

          let relaunchedSyncEngine = try await SyncEngine(
            container: syncEngine.container,
            userDatabase: syncEngine.userDatabase,
            tables: syncEngine.tables + [SynchronizedTable(for: Image.self)],
            privateTables: syncEngine.privateTables
          )
          defer { _ = relaunchedSyncEngine }

          let images = try await userDatabase.read { db in
            try Image.order(by: \.id).fetchAll(db)
          }

          expectNoDifference(
            images,
            [
              Image(id: 1, image: Data("image".utf8), caption: "A good image")
            ]
          )
        }
      }
    }
  }

  @Table("remindersLists")
  private struct RemindersListWithPosition: Equatable, Identifiable {
    let id: Int
    var title = ""
    var position = 0
  }

  @Table("reminders")
  private struct ReminderWithPosition: Equatable, Identifiable {
    let id: Int
    var title = ""
    var position = 0
    var remindersListID: RemindersList.ID
  }

  @Table("remindersLists")
  private struct RemindersListWithData: Equatable, Identifiable {
    let id: Int
    var image: Data
    var title = ""
  }

  @Table
  private struct Image: Equatable, Identifiable {
    let id: Int
    var image: Data
    var caption = ""
  }
#endif
