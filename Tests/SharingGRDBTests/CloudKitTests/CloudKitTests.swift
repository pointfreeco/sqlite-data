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
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT ''
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "INTEGER"
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
            tableName: "sqlite_sequence",
            schema: "CREATE TABLE sqlite_sequence(name,seq)",
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "name",
                notNull: false,
                type: ""
              ),
              [1]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "seq",
                notNull: false,
                type: ""
              )
            ]
          ),
          [2]: RecordType(
            tableName: "remindersListAssets",
            schema: """
              CREATE TABLE "remindersListAssets" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "coverImage" BLOB NOT NULL,
                "remindersListID" INTEGER NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
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
                defaultValue: nil,
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "INTEGER"
              ),
              [2]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "remindersListID",
                notNull: true,
                type: "INTEGER"
              )
            ]
          ),
          [3]: RecordType(
            tableName: "remindersListPrivates",
            schema: """
              CREATE TABLE "remindersListPrivates" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "position" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
                "remindersListID" INTEGER NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "INTEGER"
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
                type: "INTEGER"
              )
            ]
          ),
          [4]: RecordType(
            tableName: "reminders",
            schema: """
              CREATE TABLE "reminders" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
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
                notNull: false,
                type: "TEXT"
              ),
              [1]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "INTEGER"
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
                type: "INTEGER"
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
          [5]: RecordType(
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
                notNull: true,
                type: "TEXT"
              )
            ]
          ),
          [6]: RecordType(
            tableName: "reminderTags",
            schema: """
              CREATE TABLE "reminderTags" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "reminderID" INTEGER NOT NULL REFERENCES "reminders"("id") ON DELETE CASCADE,
                "tagID" TEXT NOT NULL REFERENCES "tags"("title") ON DELETE CASCADE ON UPDATE CASCADE
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "INTEGER"
              ),
              [1]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "reminderID",
                notNull: true,
                type: "INTEGER"
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
          [7]: RecordType(
            tableName: "parents",
            schema: """
              CREATE TABLE "parents"(
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "INTEGER"
              )
            ]
          ),
          [8]: RecordType(
            tableName: "childWithOnDeleteSetNulls",
            schema: """
              CREATE TABLE "childWithOnDeleteSetNulls"(
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "parentID" INTEGER REFERENCES "parents"("id") ON DELETE SET NULL ON UPDATE SET NULL
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "INTEGER"
              ),
              [1]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "parentID",
                notNull: false,
                type: "INTEGER"
              )
            ]
          ),
          [9]: RecordType(
            tableName: "childWithOnDeleteSetDefaults",
            schema: """
              CREATE TABLE "childWithOnDeleteSetDefaults"(
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "parentID" INTEGER NOT NULL DEFAULT 0 
                  REFERENCES "parents"("id") ON DELETE SET DEFAULT ON UPDATE SET DEFAULT
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "INTEGER"
              ),
              [1]: TableInfo(
                defaultValue: "0",
                isPrimaryKey: false,
                name: "parentID",
                notNull: true,
                type: "INTEGER"
              )
            ]
          ),
          [10]: RecordType(
            tableName: "localUsers",
            schema: """
              CREATE TABLE "localUsers" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "name" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                "parentID" INTEGER REFERENCES "localUsers"("id") ON DELETE CASCADE
              ) STRICT
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "INTEGER"
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
                type: "INTEGER"
              )
            ]
          ),
          [11]: RecordType(
            tableName: "modelAs",
            schema: """
              CREATE TABLE "modelAs" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "count" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
                "isEven" INTEGER GENERATED ALWAYS AS ("count" % 2 == 0) VIRTUAL 
              )
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: "0",
                isPrimaryKey: false,
                name: "count",
                notNull: true,
                type: "INTEGER"
              ),
              [1]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "INTEGER"
              )
            ]
          ),
          [12]: RecordType(
            tableName: "modelBs",
            schema: """
              CREATE TABLE "modelBs" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "isOn" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
                "modelAID" INTEGER NOT NULL REFERENCES "modelAs"("id") ON DELETE CASCADE
              )
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "INTEGER"
              ),
              [1]: TableInfo(
                defaultValue: "0",
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
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                "modelBID" INTEGER NOT NULL REFERENCES "modelBs"("id") ON DELETE CASCADE
              )
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "INTEGER"
              ),
              [1]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "modelBID",
                notNull: true,
                type: "INTEGER"
              ),
              [2]: TableInfo(
                defaultValue: "\'\'",
                isPrimaryKey: false,
                name: "title",
                notNull: true,
                type: "TEXT"
              )
            ]
          ),
          [14]: RecordType(
            tableName: "unsyncedModels",
            schema: """
              CREATE TABLE "unsyncedModels" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
              )
              """,
            tableInfo: [
              [0]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: true,
                name: "id",
                notNull: true,
                type: "INTEGER"
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
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      assertInlineSnapshot(of: container, as: .customDump) {
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
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      assertInlineSnapshot(of: container, as: .customDump) {
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
        try RemindersList.metadata(for: 1).fetchOne(db)
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
        ORDER BY name
        """,
        as: String.self
      )
      assertInlineSnapshot(
        of: try { try userDatabase.userRead { try query.fetchAll($0) } }(),
        as: .customDump
      ) {
        """
        [
          [0]: "sqlitedata_icloud_datetime",
          [1]: "sqlitedata_icloud_diddelete",
          [2]: "sqlitedata_icloud_didupdate",
          [3]: "sqlitedata_icloud_haspermission",
          [4]: "sqlitedata_icloud_syncengineissynchronizingchanges"
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
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      assertInlineSnapshot(of: container, as: .customDump) {
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
        $0.datetime.now.addTimeInterval(60)
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
    @Test func remoteServerRecordUpdate() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
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
          try RemindersList.metadata(for: 1)
            .select(\.userModificationDate)
            .fetchOne(db) ?? nil
        }
      )

      let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
      let serverModificationDate = userModificationDate.addingTimeInterval(60)
      record.setValue("Work", forKey: "title", at: serverModificationDate)
      try await syncEngine.modifyRecords(scope: .private, saving: [record]).notify()

      expectNoDifference(
        try { try userDatabase.userRead { db in
          try RemindersList.find(1).fetchOne(db) }
        }(),
        RemindersList(id: 1, title: "Work")
      )

      let metadata = try #require(
        try await userDatabase.userRead { db in
          try RemindersList.metadata(for: 1)
            .fetchOne(db)
        }
      )
      #expect(metadata.userModificationDate == serverModificationDate)
      assertInlineSnapshot(of: container, as: .customDump) {
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
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      try await withDependencies {
        $0.datetime.now.addTimeInterval(1)
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
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      assertInlineSnapshot(of: container, as: .customDump) {
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
          try RemindersList.metadata(for: 1)
            .select(\.userModificationDate)
            .fetchOne(db) ?? nil
        }
      )

      let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
      record.encryptedValues["title"] = "Work"
      // NB: Manually setting '_recordChangeTag' simulates another device saving a record.
      record._recordChangeTag = UUID().uuidString
      try await syncEngine.modifyRecords(scope: .private, saving: [record]).notify()

      expectNoDifference(
        try { try userDatabase.userRead { db in try RemindersList.find(1).fetchOne(db) } }(),
        RemindersList(id: 1, title: "Personal")
      )

      let metadata = try #require(
        try await userDatabase.userRead { db in
          try RemindersList.metadata(for: 1)
            .fetchOne(db)
        }
      )
      #expect(metadata.userModificationDate == userModificationDate)
      assertInlineSnapshot(of: container, as: .customDump) {
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
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      assertInlineSnapshot(of: container, as: .customDump) {
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
      try await syncEngine.modifyRecords(scope: .private, deleting: [record.recordID]).notify()

      #expect(
        try await userDatabase.userRead { db in
          try RemindersList.find(1).fetchAll(db)
        } == []
      )
      let metadata = try await userDatabase.userRead { db in
        try RemindersList.metadata(for: 1)
          .fetchOne(db)
      }
      #expect(metadata == nil)
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
            RemindersListPrivate(id: 1, position: 1, remindersListID: 1)
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
                  recordID: CKRecord.ID(fun:tags/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                  recordType: "tags",
                  parent: nil,
                  share: nil,
                  title: "fun"
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(weekend:tags/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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
  }

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
              recordID: CKRecord.ID(1:modelAs/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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
    record.encryptedValues["isEven"] = false
    try await syncEngine.modifyRecords(scope: .private, saving: [record]).notify()

    assertInlineSnapshot(of: container, as: .customDump) {
      """
      MockCloudContainer(
        privateCloudDatabase: MockCloudDatabase(
          databaseScope: .private,
          storage: [
            [0]: CKRecord(
              recordID: CKRecord.ID(1:modelAs/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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

  // TODO: Test what happens when we delete locally and then an edit comes in from the server
}
