#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import Foundation
  import InlineSnapshotTesting
  import SQLiteData
  import SQLiteDataTestSupport
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

      /*
       * Test run from perspective of old device with old schema.
       * New schema saves record in cloud database.
       * Record syncs to old device with old schema.
       * Old device edits record without access to new schema.
       => All data (new+old schema) is sync'd to cloud database.
       */
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func oldSchemaUpdatesNewSchemaRecord() async throws {
        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1)
        )
        remindersListRecord.setValue(1, forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)
        remindersListRecord.setValue(42, forKey: "position", at: 0)

        try await syncEngine.modifyRecords(scope: .private, saving: [remindersListRecord]).notify()

        try await userDatabase.userWrite { db in
          try #expect(RemindersList.fetchCount(db) == 1)
          try #expect(RemindersList.find(1).fetchOne(db) == RemindersList(id: 1, title: "Personal"))
          try RemindersList.find(1).update { $0.title = "My Stuff" }.execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
          """
          ┌────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                      │
          │   id: SyncMetadata.ID(                                             │
          │     recordPrimaryKey: "1",                                         │
          │     recordType: "remindersLists"                                   │
          │   ),                                                               │
          │   zoneName: "zone",                                                │
          │   ownerName: "__defaultOwner__",                                   │
          │   recordName: "1:remindersLists",                                  │
          │   parentRecordID: nil,                                             │
          │   parentRecordName: nil,                                           │
          │   lastKnownServerRecord: CKRecord(                                 │
          │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__), │
          │     recordType: "remindersLists",                                  │
          │     parent: nil,                                                   │
          │     share: nil                                                     │
          │   ),                                                               │
          │   _lastKnownServerRecordAllFields: CKRecord(                       │
          │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__), │
          │     recordType: "remindersLists",                                  │
          │     parent: nil,                                                   │
          │     share: nil,                                                    │
          │     id: 1,                                                         │
          │     position: 42,                                                  │
          │     title: "My Stuff"                                              │
          │   ),                                                               │
          │   share: nil,                                                      │
          │   _isDeleted: false,                                               │
          │   _hasLastKnownServerRecord: true,                                 │
          │   _isShared: false,                                                │
          │   userModificationTime: 0                                          │
          │ )                                                                  │
          └────────────────────────────────────────────────────────────────────┘
          """
        }
        assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  position: 42,
                  title: "My Stuff"
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

      /*
       * Old schema creates record and synchronizes to iCloud.
       * Schema is migrated to add a "NOT NULL" column.
       * New sync engine is launched.
       => Sync starts without emitting an error.
       */
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func addColumn_OldRecordsSyncToNewSchema() async throws {
        let remindersList = RemindersList(id: 1, title: "Personal")
        try await userDatabase.userWrite { db in
          try db.seed {
            remindersList
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        syncEngine.stop()

        try await userDatabase.userWrite { db in
          try #sql(
            """
            ALTER TABLE "remindersLists" 
            ADD COLUMN "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 42
            """
          )
          .execute(db)
        }

        // NB: Sync engine should start without emitting issue.
        _ = try await SyncEngine(
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

        try await userDatabase.read { db in
          try #expect(
            RemindersListWithPosition.fetchAll(db) == [
              RemindersListWithPosition(id: 1, title: "Personal", position: 42)
            ]
          )
        }
      }

      /*
       * Old schema creates record and synchronizes to iCloud.
       * Schema is migrated to add a "NULL DEFAULT _" column.
       * New sync engine is launched.
       => Sync starts without emitting an error and default value is persisted in local database.
       */
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func addNullableColumn_OldRecordsSyncToNewSchema() async throws {
        let remindersList = RemindersList(id: 1, title: "Personal")
        try await userDatabase.userWrite { db in
          try db.seed {
            remindersList
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        syncEngine.stop()

        try await userDatabase.userWrite { db in
          try #sql(
            """
            ALTER TABLE "remindersLists" 
            ADD COLUMN "color" INTEGER DEFAULT 42
            """
          )
          .execute(db)
        }

        // NB: Sync engine should start without emitting issue.
        _ = try await SyncEngine(
          container: syncEngine.container,
          userDatabase: syncEngine.userDatabase,
          tables: syncEngine.tables
            .filter { $0.base != RemindersList.self }
          + [
            SynchronizedTable(for: RemindersListWithColor.self),
          ],
          privateTables: syncEngine.privateTables
        )

        try await userDatabase.read { db in
          try #expect(
            RemindersListWithColor.fetchAll(db) == [
              RemindersListWithColor(id: 1, title: "Personal", color: 42)
            ]
          )
        }
      }

      /*
       * Test run from perspective of old device with old schema.
       * Old schema saves record in cloud database.
       * New device with new schema saves record with extra fields.
       => All data (new+old schema) is sync'd to old device with old schema.
       */
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func newSchemaUpdatesOldSchemaRecord() async throws {
        let remindersList = RemindersList(id: 1, title: "Personal")
        try await userDatabase.userWrite { db in
          try db.seed { remindersList }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let remindersListRecord = try syncEngine.private.database.record(
          for: RemindersList.recordID(for: 1)
        )
        remindersListRecord.setValue("My Stuff", forKey: "title", at: 1)
        remindersListRecord.setValue(42, forKey: "position", at: 1)
        try await syncEngine.modifyRecords(scope: .private, saving: [remindersListRecord]).notify()

        try await userDatabase.read { db in
          try #expect(RemindersList.find(1).fetchOne(db) == RemindersList(id: 1, title: "My Stuff"))
        }

        assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
          """
          ┌────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                      │
          │   id: SyncMetadata.ID(                                             │
          │     recordPrimaryKey: "1",                                         │
          │     recordType: "remindersLists"                                   │
          │   ),                                                               │
          │   zoneName: "zone",                                                │
          │   ownerName: "__defaultOwner__",                                   │
          │   recordName: "1:remindersLists",                                  │
          │   parentRecordID: nil,                                             │
          │   parentRecordName: nil,                                           │
          │   lastKnownServerRecord: CKRecord(                                 │
          │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__), │
          │     recordType: "remindersLists",                                  │
          │     parent: nil,                                                   │
          │     share: nil                                                     │
          │   ),                                                               │
          │   _lastKnownServerRecordAllFields: CKRecord(                       │
          │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__), │
          │     recordType: "remindersLists",                                  │
          │     parent: nil,                                                   │
          │     share: nil,                                                    │
          │     id: 1,                                                         │
          │     position: 42,                                                  │
          │     title: "My Stuff"                                              │
          │   ),                                                               │
          │   share: nil,                                                      │
          │   _isDeleted: false,                                               │
          │   _hasLastKnownServerRecord: true,                                 │
          │   _isShared: false,                                                │
          │   userModificationTime: 1                                          │
          │ )                                                                  │
          └────────────────────────────────────────────────────────────────────┘
          """
        }
        assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  position: 42,
                  title: "My Stuff"
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

      /*
       * Test run from perspective of new device with new schema.
       * Old schema saves record in cloud database.
       => Data syncs new to new device with new schema.
       * New device updates record.
       => Data syncs new to cloud database.
       */
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func runWithNewSchema_oldSchemaSavesRecord_NewSchemaUpdatesRecord() async throws {
        syncEngine.stop()
        try syncEngine.tearDownSyncEngine()

        try await userDatabase.userWrite { db in
          try #sql(
            """
            ALTER TABLE "remindersLists"
            ADD COLUMN "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
            """
          )
          .execute(db)
        }
        let newSyncEngine = try await SyncEngine(
          container: syncEngine.container,
          userDatabase: syncEngine.userDatabase,
          tables: syncEngine.tables
            .filter { $0.base != RemindersList.self }
            + [
              SynchronizedTable(for: RemindersListWithPosition.self)
            ],
          privateTables: syncEngine.privateTables
        )
        defer { _ = newSyncEngine }

        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1)
        )
        remindersListRecord.setValue(1, forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)

        try await newSyncEngine.modifyRecords(scope: .private, saving: [remindersListRecord])
          .notify()

        try await userDatabase.read { db in
          try #expect(
            RemindersListWithPosition.find(1).fetchOne(db)
              == RemindersListWithPosition(id: 1, title: "Personal", position: 0)
          )
        }

        assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
          """
          ┌────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                      │
          │   id: SyncMetadata.ID(                                             │
          │     recordPrimaryKey: "1",                                         │
          │     recordType: "remindersLists"                                   │
          │   ),                                                               │
          │   zoneName: "zone",                                                │
          │   ownerName: "__defaultOwner__",                                   │
          │   recordName: "1:remindersLists",                                  │
          │   parentRecordID: nil,                                             │
          │   parentRecordName: nil,                                           │
          │   lastKnownServerRecord: CKRecord(                                 │
          │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__), │
          │     recordType: "remindersLists",                                  │
          │     parent: nil,                                                   │
          │     share: nil                                                     │
          │   ),                                                               │
          │   _lastKnownServerRecordAllFields: CKRecord(                       │
          │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__), │
          │     recordType: "remindersLists",                                  │
          │     parent: nil,                                                   │
          │     share: nil,                                                    │
          │     id: 1,                                                         │
          │     title: "Personal"                                              │
          │   ),                                                               │
          │   share: nil,                                                      │
          │   _isDeleted: false,                                               │
          │   _hasLastKnownServerRecord: true,                                 │
          │   _isShared: false,                                                │
          │   userModificationTime: 0                                          │
          │ )                                                                  │
          └────────────────────────────────────────────────────────────────────┘
          """
        }

        try await userDatabase.userWrite { db in
          try RemindersListWithPosition.find(1).update {
            $0.title = "My Stuff"
            $0.position = 42
          }
          .execute(db)
        }
        try await newSyncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
          """
          ┌────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                      │
          │   id: SyncMetadata.ID(                                             │
          │     recordPrimaryKey: "1",                                         │
          │     recordType: "remindersLists"                                   │
          │   ),                                                               │
          │   zoneName: "zone",                                                │
          │   ownerName: "__defaultOwner__",                                   │
          │   recordName: "1:remindersLists",                                  │
          │   parentRecordID: nil,                                             │
          │   parentRecordName: nil,                                           │
          │   lastKnownServerRecord: CKRecord(                                 │
          │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__), │
          │     recordType: "remindersLists",                                  │
          │     parent: nil,                                                   │
          │     share: nil                                                     │
          │   ),                                                               │
          │   _lastKnownServerRecordAllFields: CKRecord(                       │
          │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__), │
          │     recordType: "remindersLists",                                  │
          │     parent: nil,                                                   │
          │     share: nil,                                                    │
          │     id: 1,                                                         │
          │     position: 42,                                                  │
          │     title: "My Stuff"                                              │
          │   ),                                                               │
          │   share: nil,                                                      │
          │   _isDeleted: false,                                               │
          │   _hasLastKnownServerRecord: true,                                 │
          │   _isShared: false,                                                │
          │   userModificationTime: 0                                          │
          │ )                                                                  │
          └────────────────────────────────────────────────────────────────────┘
          """
        }
        assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  position: 42,
                  title: "My Stuff"
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

  @Table("remindersLists")
  private struct RemindersListWithColor: Equatable, Identifiable {
    let id: Int
    var title = ""
    var color: Int?
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
