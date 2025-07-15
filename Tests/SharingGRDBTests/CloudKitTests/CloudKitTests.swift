import CloudKit
import ConcurrencyExtras
import CustomDump
import InlineSnapshotTesting
import OrderedCollections
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class CloudKitTests: BaseCloudKitTests, @unchecked Sendable {
    @Dependency(\.date.now) var now

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func setUp() throws {
      let zones = try userDatabase.userRead { db in
        try RecordType.all.fetchAll(db)
      }
      assertInlineSnapshot(of: zones, as: .customDump) {
        #"""
        [
          [0]: RecordType(
            tableName: "remindersLists",
            schema: """
              CREATE TABLE "remindersLists" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: "uuid()",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              ),
              [1]: TableInfo(
                defaultValue: "\'\'",
                isPrimaryKey: false,
                name: "title",
                notNull: true,
                type: "TEXT"
              )
            ]
          ),
          [1]: RecordType(
            tableName: "remindersListAssets",
            schema: """
              CREATE TABLE "remindersListAssets" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "coverImage" BLOB NOT NULL,
                "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "coverImage",
                notNull: true,
                type: "BLOB"
              ),
              [1]: TableInfo(
                defaultValue: "uuid()",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              ),
              [2]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "remindersListID",
                notNull: true,
                type: "TEXT"
              )
            ]
          ),
          [2]: RecordType(
            tableName: "remindersListPrivates",
            schema: """
              CREATE TABLE "remindersListPrivates" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
                "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: "uuid()",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              ),
              [1]: TableInfo(
                defaultValue: "0",
                isPrimaryKey: false,
                name: "position",
                notNull: true,
                type: "INTEGER"
              ),
              [2]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "remindersListID",
                notNull: true,
                type: "TEXT"
              )
            ]
          ),
          [3]: RecordType(
            tableName: "reminders",
            schema: """
              CREATE TABLE "reminders" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "dueDate" TEXT,
                "isCompleted" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
                "priority" INTEGER,
                "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                "remindersListID" TEXT NOT NULL, 
                
                FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "dueDate",
                notNull: false,
                type: "TEXT"
              ),
              [1]: TableInfo(
                defaultValue: "uuid()",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              ),
              [2]: TableInfo(
                defaultValue: "0",
                isPrimaryKey: false,
                name: "isCompleted",
                notNull: true,
                type: "INTEGER"
              ),
              [3]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "priority",
                notNull: false,
                type: "INTEGER"
              ),
              [4]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "remindersListID",
                notNull: true,
                type: "TEXT"
              ),
              [5]: TableInfo(
                defaultValue: "\'\'",
                isPrimaryKey: false,
                name: "title",
                notNull: true,
                type: "TEXT"
              )
            ]
          ),
          [4]: RecordType(
            tableName: "tags",
            schema: """
              CREATE TABLE "tags" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: "uuid()",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              ),
              [1]: TableInfo(
                defaultValue: "\'\'",
                isPrimaryKey: false,
                name: "title",
                notNull: true,
                type: "TEXT"
              )
            ]
          ),
          [5]: RecordType(
            tableName: "reminderTags",
            schema: """
              CREATE TABLE "reminderTags" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "reminderID" TEXT NOT NULL REFERENCES "reminders"("id") ON DELETE CASCADE,
                "tagID" TEXT NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: "uuid()",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              ),
              [1]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "reminderID",
                notNull: true,
                type: "TEXT"
              ),
              [2]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "tagID",
                notNull: true,
                type: "TEXT"
              )
            ]
          ),
          [6]: RecordType(
            tableName: "parents",
            schema: """
              CREATE TABLE "parents"(
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: "uuid()",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              )
            ]
          ),
          [7]: RecordType(
            tableName: "childWithOnDeleteRestricts",
            schema: """
              CREATE TABLE "childWithOnDeleteRestricts"(
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "parentID" TEXT NOT NULL REFERENCES "parents"("id") ON DELETE RESTRICT ON UPDATE RESTRICT
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: "uuid()",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              ),
              [1]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "parentID",
                notNull: true,
                type: "TEXT"
              )
            ]
          ),
          [8]: RecordType(
            tableName: "childWithOnDeleteSetNulls",
            schema: """
              CREATE TABLE "childWithOnDeleteSetNulls"(
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "parentID" TEXT REFERENCES "parents"("id") ON DELETE SET NULL ON UPDATE SET NULL
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: "uuid()",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              ),
              [1]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "parentID",
                notNull: false,
                type: "TEXT"
              )
            ]
          ),
          [9]: RecordType(
            tableName: "childWithOnDeleteSetDefaults",
            schema: """
              CREATE TABLE "childWithOnDeleteSetDefaults"(
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT '00000000-0000-0000-0000-000000000000',
                "parentID" TEXT REFERENCES "parents"("id") ON DELETE SET DEFAULT ON UPDATE SET DEFAULT
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: "\'00000000-0000-0000-0000-000000000000\'",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              ),
              [1]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "parentID",
                notNull: false,
                type: "TEXT"
              )
            ]
          ),
          [10]: RecordType(
            tableName: "localUsers",
            schema: """
              CREATE TABLE "localUsers" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                "parentID" TEXT REFERENCES "localUsers"("id") ON DELETE CASCADE
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: "uuid()",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              ),
              [1]: TableInfo(
                defaultValue: "\'\'",
                isPrimaryKey: false,
                name: "name",
                notNull: true,
                type: "TEXT"
              ),
              [2]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "parentID",
                notNull: false,
                type: "TEXT"
              )
            ]
          ),
          [11]: RecordType(
            tableName: "modelAs",
            schema: """
              CREATE TABLE "modelAs" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "count" INTEGER NOT NULL
              )
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "count",
                notNull: true,
                type: "INTEGER"
              ),
              [1]: TableInfo(
                defaultValue: "uuid()",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              )
            ]
          ),
          [12]: RecordType(
            tableName: "modelBs",
            schema: """
              CREATE TABLE "modelBs" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "isOn" INTEGER NOT NULL,
                "modelAID" INTEGER NOT NULL REFERENCES "modelAs"("id") ON DELETE CASCADE
              )
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: "uuid()",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              ),
              [1]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "isOn",
                notNull: true,
                type: "INTEGER"
              ),
              [2]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "modelAID",
                notNull: true,
                type: "INTEGER"
              )
            ]
          ),
          [13]: RecordType(
            tableName: "modelCs",
            schema: """
              CREATE TABLE "modelCs" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "title" TEXT NOT NULL,
                "modelBID" INTEGER NOT NULL REFERENCES "modelBs"("id") ON DELETE CASCADE
              )
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: "uuid()",
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "TEXT"
              ),
              [1]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "modelBID",
                notNull: true,
                type: "INTEGER"
              ),
              [2]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "title",
                notNull: true,
                type: "TEXT"
              )
            ]
          )
        ]
        """#
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func tearDown() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
        }
      }
      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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

      try await userDatabase.userRead { db in
        let metadataCount = try SyncMetadata.count().fetchOne(db) ?? 0
        #expect(metadataCount == 1)
      }
      try await syncEngine.tearDownSyncEngine()
      try await self.userDatabase.userRead { db in
        let metadataCount = try SyncMetadata.count().fetchOne(db) ?? 0
        #expect(metadataCount == 0)
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func tearDownAndReSetUp() async throws {
      try await syncEngine.tearDownSyncEngine()
      try await syncEngine.setUpSyncEngine()

      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
        }
      }
      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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

      let metadata =
      try await userDatabase.userRead { db in
        try SyncMetadata.find(1, table: RemindersList.self).fetchOne(db)
      }
      #expect(metadata != nil)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func addAndRemoveFunctions() async throws {
      let query = #sql(
        """
        SELECT name
        FROM pragma_function_list
        WHERE name LIKE \(bind: String.sqliteDataCloudKitSchemaName + "_%")
        """,
        as: String.self
      )
      assertInlineSnapshot(
        of: try { try userDatabase.userRead { try query.fetchAll($0) } }(),
        as: .customDump
      ) {
        """
        [
          [0]: "sqlitedata_icloud_syncengineisupdatingrecord",
          [1]: "sqlitedata_icloud_datetime",
          [2]: "sqlitedata_icloud_didupdate",
          [3]: "sqlitedata_icloud_diddelete"
        ]
        """
      }
      try await syncEngine.tearDownSyncEngine()

      assertInlineSnapshot(
        of: try { try userDatabase.userRead { try query.fetchAll($0) } }(),
        as: .customDump
      ) {
        """
        []
        """
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func migration() async throws {
      // TODO: how to test what happens after a migration? need to assert that zones are fetched.
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func insertUpdateDelete() async throws {
      try await userDatabase.userWrite { db in
        try RemindersList
          .insert { RemindersList(id: 1, title: "Personal") }
          .execute(db)
      }
      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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
        $0.date.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try RemindersList
            .find(1)
            .update { $0.title = "Work" }
            .execute(db)
        }
      }
      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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
      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
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
    @Test func remoteServerRecordUpdate() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
        }
      }
      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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

      let userModificationDate = try #require(
        try await userDatabase.userRead { db in
          try SyncMetadata
            .find(1, table: RemindersList.self)
            .select(\.userModificationDate)
            .fetchOne(db) ?? nil
        }
      )

      let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
      let serverModificationDate = userModificationDate.addingTimeInterval(60)
      record.setValue("Work", forKey: "title", at: serverModificationDate)
      _ = await syncEngine.modifyRecords(scope: .private, saving: [record])

      expectNoDifference(
        try { try userDatabase.userRead { db in
          try RemindersList.find(1).fetchOne(db) }
        }(),
        RemindersList(id: 1, title: "Work")
      )

      let metadata = try #require(
        try await userDatabase.userRead { db in
          try SyncMetadata
            .find(1, table: RemindersList.self)
            .fetchOne(db)
        }
      )
      #expect(metadata.userModificationDate == serverModificationDate)
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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
      await syncEngine.processBatch()

      try await withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try await userDatabase.userWrite { db in
          try RemindersList.find(1).update { $0.title = "My stuff" }.execute(db)
        }
      }

      let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
      await syncEngine.modifyRecords(scope: .private, saving: [record])
      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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
      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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

      let userModificationDate = try #require(
        try await userDatabase.userRead { db in
          try SyncMetadata
            .find(1, table: RemindersList.self)
            .select(\.userModificationDate)
            .fetchOne(db) ?? nil
        }
      )

      let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
      record.encryptedValues["title"] = "Work"
      // NB: Manually setting '_recordChangeTag' simulates another device saving a record.
      record._recordChangeTag = UUID().uuidString
      await syncEngine.modifyRecords(scope: .private, saving: [record])

      expectNoDifference(
        try { try userDatabase.userRead { db in try RemindersList.find(1).fetchOne(db) } }(),
        RemindersList(id: 1, title: "Personal")
      )

      let metadata = try #require(
        try await userDatabase.userRead { db in
          try SyncMetadata
            .find(1, table: RemindersList.self)
            .fetchOne(db)
        }
      )
      #expect(metadata.userModificationDate == userModificationDate)
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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
      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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

      let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
      await syncEngine.modifyRecords(scope: .private, deleting: [record.recordID])

      #expect(
        try await userDatabase.userRead { db in
          try RemindersList.find(1).fetchAll(db)
        } == []
      )
      let metadata = try await userDatabase.userRead { db in
        try SyncMetadata
          .find(1, table: RemindersList.self)
          .fetchOne(db)
      }
      #expect(metadata == nil)
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
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

    @Test func cascadingDeletionOrder() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          Tag(id: 1, title: "")
          Tag(id: 2, title: "")
        }
      }
      for _ in 1...100 {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersListPrivate(id: 1, position: 1, remindersListID: 1)
            Reminder(id: 1, title: "", remindersListID: 1)
            Reminder(id: 2, title: "", remindersListID: 1)
            Reminder(id: 3, title: "", remindersListID: 1)
            Reminder(id: 4, title: "", remindersListID: 1)
            ReminderTag(id: 1, reminderID: 1, tagID: 1)
            ReminderTag(id: 2, reminderID: 2, tagID: 1)
            ReminderTag(id: 3, reminderID: 3, tagID: 1)
            ReminderTag(id: 4, reminderID: 4, tagID: 1)
            ReminderTag(id: 5, reminderID: 1, tagID: 2)
            ReminderTag(id: 6, reminderID: 2, tagID: 2)
            ReminderTag(id: 7, reminderID: 3, tagID: 2)
            ReminderTag(id: 8, reminderID: 4, tagID: 2)
          }
        }

        await syncEngine.processBatch()

        try await userDatabase.userWrite { db in
          try RemindersList.find(1).delete().execute(db)
        }

        await syncEngine.processBatch()
        assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:tags/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                  recordType: "tags",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: ""
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(2:tags/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                  recordType: "tags",
                  parent: nil,
                  share: nil,
                  id: 2,
                  title: ""
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
  }

  // TODO: Test what happens when we delete locally and then an edit comes in from the server
}
