#if canImport(CloudKit)
  import CloudKit
  import ConcurrencyExtras
  import CustomDump
  import InlineSnapshotTesting
  import OrderedCollections
  import SQLiteData
  import SQLiteDataTestSupport
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class CloudKitTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func setUp() throws {
        let zones = try syncEngine.metadatabase.read { db in
          try RecordType.all.fetchAll(db)
        }
        assertInlineSnapshot(of: zones, as: .customDump) {
          #"""
          [
            [0]: RecordType(
              tableName: "remindersLists",
              schema: """
                CREATE TABLE "remindersLists" (
                  "id" INT PRIMARY KEY NOT NULL,
                  "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
                ) STRICT
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INT"
                ),
                [1]: TableInfo(
                  defaultValue: "\'\'",
                  isPrimaryKey: false,
                  name: "title",
                  isNotNull: true,
                  type: "TEXT"
                )
              ]
            ),
            [1]: RecordType(
              tableName: "remindersListAssets",
              schema: """
                CREATE TABLE "remindersListAssets" (
                  "remindersListID" INTEGER NOT NULL PRIMARY KEY
                    REFERENCES "remindersLists"("id") ON DELETE CASCADE,
                  "coverImage" BLOB NOT NULL
                ) STRICT
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: false,
                  name: "coverImage",
                  isNotNull: true,
                  type: "BLOB"
                ),
                [1]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "remindersListID",
                  isNotNull: true,
                  type: "INTEGER"
                )
              ]
            ),
            [2]: RecordType(
              tableName: "remindersListPrivates",
              schema: """
                CREATE TABLE "remindersListPrivates" (
                  "remindersListID" INTEGER PRIMARY KEY NOT NULL REFERENCES "remindersLists"("id") 
                    ON DELETE CASCADE,
                  "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
                ) STRICT
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: "0",
                  isPrimaryKey: false,
                  name: "position",
                  isNotNull: true,
                  type: "INTEGER"
                ),
                [1]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "remindersListID",
                  isNotNull: true,
                  type: "INTEGER"
                )
              ]
            ),
            [3]: RecordType(
              tableName: "reminders",
              schema: """
                CREATE TABLE "reminders" (
                  "id" INT PRIMARY KEY NOT NULL,
                  "dueDate" TEXT,
                  "isCompleted" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
                  "priority" INTEGER,
                  "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "remindersListID" INTEGER NOT NULL,
                  
                  FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
                ) STRICT
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: false,
                  name: "dueDate",
                  isNotNull: false,
                  type: "TEXT"
                ),
                [1]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INT"
                ),
                [2]: TableInfo(
                  defaultValue: "0",
                  isPrimaryKey: false,
                  name: "isCompleted",
                  isNotNull: true,
                  type: "INTEGER"
                ),
                [3]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: false,
                  name: "priority",
                  isNotNull: false,
                  type: "INTEGER"
                ),
                [4]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: false,
                  name: "remindersListID",
                  isNotNull: true,
                  type: "INTEGER"
                ),
                [5]: TableInfo(
                  defaultValue: "\'\'",
                  isPrimaryKey: false,
                  name: "title",
                  isNotNull: true,
                  type: "TEXT"
                )
              ]
            ),
            [4]: RecordType(
              tableName: "tags",
              schema: """
                CREATE TABLE "tags" (
                  "title" TEXT PRIMARY KEY NOT NULL COLLATE NOCASE 
                ) STRICT
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "title",
                  isNotNull: true,
                  type: "TEXT"
                )
              ]
            ),
            [5]: RecordType(
              tableName: "reminderTags",
              schema: """
                CREATE TABLE "reminderTags" (
                  "id" INT PRIMARY KEY NOT NULL,
                  "reminderID" INTEGER NOT NULL REFERENCES "reminders"("id") ON DELETE CASCADE,
                  "tagID" TEXT NOT NULL REFERENCES "tags"("title") ON DELETE CASCADE ON UPDATE CASCADE
                ) STRICT
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INT"
                ),
                [1]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: false,
                  name: "reminderID",
                  isNotNull: true,
                  type: "INTEGER"
                ),
                [2]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: false,
                  name: "tagID",
                  isNotNull: true,
                  type: "TEXT"
                )
              ]
            ),
            [6]: RecordType(
              tableName: "parents",
              schema: """
                CREATE TABLE "parents"(
                  "id" INT PRIMARY KEY NOT NULL
                ) STRICT
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INT"
                )
              ]
            ),
            [7]: RecordType(
              tableName: "childWithOnDeleteSetNulls",
              schema: """
                CREATE TABLE "childWithOnDeleteSetNulls"(
                  "id" INT PRIMARY KEY NOT NULL,
                  "parentID" INTEGER REFERENCES "parents"("id") ON DELETE SET NULL ON UPDATE SET NULL
                ) STRICT
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INT"
                ),
                [1]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: false,
                  name: "parentID",
                  isNotNull: false,
                  type: "INTEGER"
                )
              ]
            ),
            [8]: RecordType(
              tableName: "childWithOnDeleteSetDefaults",
              schema: """
                CREATE TABLE "childWithOnDeleteSetDefaults"(
                  "id" INT PRIMARY KEY NOT NULL,
                  "parentID" INTEGER NOT NULL DEFAULT 0 
                    REFERENCES "parents"("id") ON DELETE SET DEFAULT ON UPDATE SET DEFAULT
                ) STRICT
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INT"
                ),
                [1]: TableInfo(
                  defaultValue: "0",
                  isPrimaryKey: false,
                  name: "parentID",
                  isNotNull: true,
                  type: "INTEGER"
                )
              ]
            ),
            [9]: RecordType(
              tableName: "modelAs",
              schema: """
                CREATE TABLE "modelAs" (
                  "id" INT PRIMARY KEY NOT NULL,
                  "count" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
                  "isEven" INTEGER GENERATED ALWAYS AS ("count" % 2 == 0) VIRTUAL 
                )
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: "0",
                  isPrimaryKey: false,
                  name: "count",
                  isNotNull: true,
                  type: "INTEGER"
                ),
                [1]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INT"
                )
              ]
            ),
            [10]: RecordType(
              tableName: "modelBs",
              schema: """
                CREATE TABLE "modelBs" (
                  "id" INT PRIMARY KEY NOT NULL,
                  "isOn" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
                  "modelAID" INTEGER NOT NULL REFERENCES "modelAs"("id") ON DELETE CASCADE
                )
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INT"
                ),
                [1]: TableInfo(
                  defaultValue: "0",
                  isPrimaryKey: false,
                  name: "isOn",
                  isNotNull: true,
                  type: "INTEGER"
                ),
                [2]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: false,
                  name: "modelAID",
                  isNotNull: true,
                  type: "INTEGER"
                )
              ]
            ),
            [11]: RecordType(
              tableName: "modelCs",
              schema: """
                CREATE TABLE "modelCs" (
                  "id" INT PRIMARY KEY NOT NULL,
                  "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "modelBID" INTEGER NOT NULL REFERENCES "modelBs"("id") ON DELETE CASCADE
                )
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INT"
                ),
                [1]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: false,
                  name: "modelBID",
                  isNotNull: true,
                  type: "INTEGER"
                ),
                [2]: TableInfo(
                  defaultValue: "\'\'",
                  isPrimaryKey: false,
                  name: "title",
                  isNotNull: true,
                  type: "TEXT"
                )
              ]
            ),
            [12]: RecordType(
              tableName: "posts",
              schema: """
                CREATE TABLE "posts" (
                  "id" INT PRIMARY KEY NOT NULL,
                  "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "body" TEXT,
                  "isPublished" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
                ) STRICT
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: false,
                  name: "body",
                  isNotNull: false,
                  type: "TEXT"
                ),
                [1]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INT"
                ),
                [2]: TableInfo(
                  defaultValue: "0",
                  isPrimaryKey: false,
                  name: "isPublished",
                  isNotNull: true,
                  type: "INTEGER"
                ),
                [3]: TableInfo(
                  defaultValue: "\'\'",
                  isPrimaryKey: false,
                  name: "title",
                  isNotNull: true,
                  type: "TEXT"
                )
              ]
            ),
            [13]: RecordType(
              tableName: "scopedModels",
              schema: """
                CREATE TABLE "scopedModels" (
                  "id" INT PRIMARY KEY NOT NULL,
                  "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                  "isDeleted" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
                ) STRICT
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INT"
                ),
                [1]: TableInfo(
                  defaultValue: "0",
                  isPrimaryKey: false,
                  name: "isDeleted",
                  isNotNull: true,
                  type: "INTEGER"
                ),
                [2]: TableInfo(
                  defaultValue: "\'\'",
                  isPrimaryKey: false,
                  name: "title",
                  isNotNull: true,
                  type: "TEXT"
                )
              ]
            )
          ]
          """#
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func tearDownAndReSetUp() async throws {
        try syncEngine.tearDownSyncEngine()
        try syncEngine.setUpSyncEngine()
        try await syncEngine.start()

        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertQuery(SyncMetadata.select(\.recordName), database: syncEngine.metadatabase) {
          """
          ┌────────────────────┐
          │ "1:remindersLists" │
          └────────────────────┘
          """
        }
        assertInlineSnapshot(of: container, as: .customDump) {
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
      @Test func addAndRemoveFunctions() async throws {
        let query = #sql(
          """
          SELECT name
          FROM pragma_function_list
          WHERE name LIKE \(bind: String.sqliteDataCloudKitSchemaName + "_%")
          ORDER BY name
          """,
          as: String.self
        )
        assertInlineSnapshot(
          of: try { try userDatabase.write { try query.fetchAll($0) } }(),
          as: .customDump
        ) {
          """
          [
            [0]: "sqlitedata_icloud_currentownername",
            [1]: "sqlitedata_icloud_currenttime",
            [2]: "sqlitedata_icloud_currentzonename",
            [3]: "sqlitedata_icloud_diddelete",
            [4]: "sqlitedata_icloud_didupdate",
            [5]: "sqlitedata_icloud_haspermission",
            [6]: "sqlitedata_icloud_syncengineissynchronizingchanges"
          ]
          """
        }
        try syncEngine.tearDownSyncEngine()

        assertInlineSnapshot(
          of: try { try userDatabase.read { try query.fetchAll($0) } }(),
          as: .customDump
        ) {
          """
          []
          """
        }

        try syncEngine.setUpSyncEngine()
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func insertUpdateDelete() async throws {
        try await userDatabase.userWrite { db in
          try RemindersList
            .insert { RemindersList(id: 1, title: "Personal") }
            .execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        assertInlineSnapshot(of: container, as: .customDump) {
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
          $0.currentTime.now += 60
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList
              .find(1)
              .update { $0.title = "Work" }
              .execute(db)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        assertInlineSnapshot(of: container, as: .customDump) {
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
                  title: "Work"
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

        try await userDatabase.userWrite { db in
          try RemindersList
            .find(1)
            .delete()
            .execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        assertInlineSnapshot(of: container, as: .customDump) {
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
      @Test func `writes outside of a transaction are sent to CloudKit`() async throws {
        try await userDatabase.database.writeWithoutTransaction { db in
          #expect(!db.isInsideTransaction)
          try RemindersList.insert { RemindersList(id: 1, title: "Personal") }.execute(db)
        }
        #expect(
          syncEngine.private.state.pendingRecordZoneChanges == [
            .saveRecord(RemindersList.recordID(for: 1))
          ]
        )
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        let record = try container.privateCloudDatabase.record(for: RemindersList.recordID(for: 1))
        #expect(record.encryptedValues["title"] as? String == "Personal")

        try await userDatabase.database.writeWithoutTransaction { db in
          #expect(!db.isInsideTransaction)
          try RemindersList.find(1).delete().execute(db)
        }
        #expect(
          syncEngine.private.state.pendingRecordZoneChanges == [
            .deleteRecord(RemindersList.recordID(for: 1))
          ]
        )
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        #expect(throws: CKError.self) {
          try container.privateCloudDatabase.record(for: RemindersList.recordID(for: 1))
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `delete rolled back to a savepoint is not sent to CloudKit`() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersList(id: 2, title: "Work")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.userWrite { db in
          try db.inSavepoint {
            try RemindersList.find(1).delete().execute(db)
            return .rollback
          }
          try RemindersList.find(2).update { $0.title = "Business" }.execute(db)
        }
        #expect(
          syncEngine.private.state.pendingRecordZoneChanges == [
            .saveRecord(RemindersList.recordID(for: 2))
          ]
        )
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let record = try container.privateCloudDatabase.record(for: RemindersList.recordID(for: 1))
        #expect(record.encryptedValues["title"] as? String == "Personal")
        let metadata = try await syncEngine.metadatabase.read { db in
          try SyncMetadata.find(RemindersList.recordID(for: 1)).fetchOne(db)
        }
        #expect(metadata != nil)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `rolled back delete is not sent to CloudKit`() async throws {
        struct RollBack: Error {}

        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Personal") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        await #expect(throws: RollBack.self) {
          try await self.userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
            throw RollBack()
          }
        }
        #expect(syncEngine.private.state.pendingRecordZoneChanges.isEmpty)

        let remindersList = try await userDatabase.read { db in
          try RemindersList.find(1).fetchOne(db)
        }
        #expect(remindersList?.title == "Personal")

        let metadata = try await syncEngine.metadatabase.read { db in
          try SyncMetadata.find(RemindersList.recordID(for: 1)).fetchOne(db)
        }
        #expect(metadata != nil)

        let record = try container.privateCloudDatabase.record(for: RemindersList.recordID(for: 1))
        #expect(record.encryptedValues["title"] as? String == "Personal")
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `rolled back reinsert does not cancel a committed delete`() async throws {
        struct RollBack: Error {}

        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Personal") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.userWrite { db in
          try RemindersList.find(1).delete().execute(db)
        }
        await #expect(throws: RollBack.self) {
          try await self.userDatabase.userWrite { db in
            try RemindersList.insert { RemindersList(id: 1, title: "Reinserted") }.execute(db)
            throw RollBack()
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let remindersList = try await userDatabase.read { db in
          try RemindersList.find(1).fetchOne(db)
        }
        #expect(remindersList == nil)

        let metadata = try await syncEngine.metadatabase.read { db in
          try SyncMetadata.find(RemindersList.recordID(for: 1)).fetchOne(db)
        }
        #expect(metadata == nil)

        #expect(throws: (any Error).self) {
          try container.privateCloudDatabase.record(for: RemindersList.recordID(for: 1))
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test(.bug("https://github.com/pointfreeco/sqlite-data/issues/418"))
      func `reinserting a deleted record before sending saves it to CloudKit`() async throws {
        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Original") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.userWrite { db in
          try RemindersList.find(1).delete().execute(db)
        }
        try await userDatabase.userWrite { db in
          try RemindersList.insert { RemindersList(id: 1, title: "Reinserted") }.execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let remindersList = try await userDatabase.read { db in
          try RemindersList.find(1).fetchOne(db)
        }
        #expect(remindersList?.title == "Reinserted")

        let record = try container.privateCloudDatabase.record(
          for: RemindersList.recordID(for: 1)
        )
        #expect(record.encryptedValues["title"] as? String == "Reinserted")
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test(.bug("https://github.com/pointfreeco/sqlite-data/issues/418"))
      func `reinserting a deleted record with a new parent before sending updates its parent`()
        async throws
      {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersList(id: 2, title: "Work")
            Reminder(id: 1, title: "Groceries", remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.userWrite { db in
          try Reminder.find(1).delete().execute(db)
        }
        try await userDatabase.userWrite { db in
          try Reminder.insert {
            Reminder(id: 1, title: "Groceries", remindersListID: 2)
          }
          .execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let metadata = try await syncEngine.metadatabase.read { db in
          try SyncMetadata.find(Reminder.recordID(for: 1)).fetchOne(db)
        }
        #expect(metadata?.parentRecordName == RemindersList.recordName(for: 2))

        let record = try container.privateCloudDatabase.record(for: Reminder.recordID(for: 1))
        #expect(record.parent?.recordID == RemindersList.recordID(for: 2))
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func remoteServerRecordUpdate() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 60
        } operation: {
          let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
          record.setValue("Work", forKey: "title", at: now)
          try await syncEngine.modifyRecords(scope: .private, saving: [record]).notify()
        }

        assertQuery(RemindersList.all, database: userDatabase.database) {
          """
          ┌─────────────────┐
          │ RemindersList(  │
          │   id: 1,        │
          │   title: "Work" │
          │ )               │
          └─────────────────┘
          """
        }
        assertQuery(
          SyncMetadata.select(\.userModificationTime),
          database: syncEngine.metadatabase
        ) {
          """
          ┌────┐
          │ 60 │
          └────┘
          """
        }
        assertInlineSnapshot(of: container, as: .customDump) {
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
                  title: "Work"
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
      @Test func remoteServerSendsRecordWithNoChanges() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).update { $0.title = "My stuff" }.execute(db)
          }
        }

        let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
        try await syncEngine.modifyRecords(scope: .private, saving: [record]).notify()
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        assertInlineSnapshot(of: container, as: .customDump) {
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
                  title: "My stuff"
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
      @Test func remoteServerRecordUpdateWithOldRecord() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
        record.setValue("Work", forKey: "title", at: now)
        // NB: Manually setting '_recordChangeTag' simulates another device saving a record.
        record._recordChangeTag = .random(in: 9999 ... .max)
        try await syncEngine.modifyRecords(scope: .private, saving: [record]).notify()

        assertQuery(Reminder.all, database: userDatabase.database) {
          """
          (No results)
          """
        }
        assertQuery(
          SyncMetadata.select(\.userModificationTime),
          database: syncEngine.metadatabase
        ) {
          """
          ┌───┐
          │ 0 │
          └───┘
          """
        }
        assertInlineSnapshot(of: container, as: .customDump) {
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
      @Test func remoteServerRecordDeleted() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await syncEngine.modifyRecords(
          scope: .private,
          deleting: [RemindersList.recordID(for: 1)]
        )
        .notify()

        assertQuery(RemindersList.all, database: userDatabase.database) {
          """
          (No results)
          """
        }
        assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
          """
          (No results)
          """
        }
        assertInlineSnapshot(of: container, as: .customDump) {
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
      @Test func cascadingDeletionOrder() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            Tag(title: "fun")
            Tag(title: "weekend")
          }
        }
        for _ in 1...100 {
          try await userDatabase.userWrite { db in
            try db.seed {
              RemindersList(id: 1, title: "Personal")
              RemindersListPrivate(remindersListID: 1, position: 1)
              Reminder(id: 1, title: "", remindersListID: 1)
              Reminder(id: 2, title: "", remindersListID: 1)
              Reminder(id: 3, title: "", remindersListID: 1)
              Reminder(id: 4, title: "", remindersListID: 1)
              ReminderTag(id: 1, reminderID: 1, tagID: "fun")
              ReminderTag(id: 2, reminderID: 2, tagID: "fun")
              ReminderTag(id: 3, reminderID: 3, tagID: "fun")
              ReminderTag(id: 4, reminderID: 4, tagID: "fun")
              ReminderTag(id: 5, reminderID: 1, tagID: "weekend")
              ReminderTag(id: 6, reminderID: 2, tagID: "weekend")
              ReminderTag(id: 7, reminderID: 3, tagID: "weekend")
              ReminderTag(id: 8, reminderID: 4, tagID: "weekend")
            }
          }

          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

          try await userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
          }

          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
          assertInlineSnapshot(of: container, as: .customDump) {
            """
            MockCloudContainer(
              privateCloudDatabase: MockCloudDatabase(
                databaseScope: .private,
                storage: [
                  [0]: CKRecord(
                    recordID: CKRecord.ID(fun:tags/zone/__defaultOwner__),
                    recordType: "tags",
                    parent: nil,
                    share: nil,
                    title: "fun"
                  ),
                  [1]: CKRecord(
                    recordID: CKRecord.ID(weekend:tags/zone/__defaultOwner__),
                    recordType: "tags",
                    parent: nil,
                    share: nil,
                    title: "weekend"
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
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func sendChanges() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        try await syncEngine.sendChanges(CKSyncEngine.SendChangesOptions())
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func generatedColumns() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            ModelA(id: 1, count: 42, isEven: true)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:modelAs/zone/__defaultOwner__),
                  recordType: "modelAs",
                  parent: nil,
                  share: nil,
                  count: 42,
                  id: 1
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

        let record = try syncEngine.private.database.record(for: ModelA.recordID(for: 1))
        record.setValue(false, forKey: "isEven", at: 0)
        try await syncEngine.modifyRecords(scope: .private, saving: [record]).notify()

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:modelAs/zone/__defaultOwner__),
                  recordType: "modelAs",
                  parent: nil,
                  share: nil,
                  count: 42,
                  id: 1,
                  isEven: 0
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

        try await userDatabase.read { db in
          let modelA = try #require(try ModelA.find(1).fetchOne(db))
          #expect(modelA.isEven == true)
        }
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func sendParentsBeforeChildren() async throws {
      try await userDatabase.userWrite { db in
        for id in 1...30 {
          try RemindersList.insert { RemindersList(id: id, title: "List \(id)") }.execute(db)
        }
        for id in 1...30 {
          try ScopedModel.insert { ScopedModel(id: id, title: "Model \(id)") }.execute(db)
        }
        for id in 1...30 {
          try Reminder.insert {
            Reminder(id: id, title: "Reminder \(id)", remindersListID: id)
          }
          .execute(db)
        }
      }

      let batch = try #require(
        await syncEngine.nextRecordZoneChangeBatch(syncEngine: syncEngine.private)
      )
      let recordTypes = batch.recordsToSave.map(\.recordType)
      let lastListIndex = try #require(recordTypes.lastIndex(of: RemindersList.tableName))
      let firstReminderIndex = try #require(recordTypes.firstIndex(of: Reminder.tableName))
      #expect(lastListIndex < firstReminderIndex)
    }
  }
#endif
