#if canImport(CloudKit)
  import CloudKit
  import ConcurrencyExtras
  import CustomDump
  import InlineSnapshotTesting
  import SQLiteData
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class RecordTypeTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func setUp() async throws {
        let recordTypes = try await syncEngine.metadatabase.read { db in
          try RecordType.all.fetchAll(db)
        }
        assertInlineSnapshot(of: recordTypes, as: .customDump) {
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
                  isNotNull: true,
                  type: "INTEGER"
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
                  isNotNull: false,
                  type: "TEXT"
                ),
                [1]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INTEGER"
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
                  isNotNull: true,
                  type: "INTEGER"
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
                  "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL
                ) STRICT
                """,
              tableInfo: [
                [0]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INTEGER"
                )
              ]
            ),
            [7]: RecordType(
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
                  isNotNull: true,
                  type: "INTEGER"
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
                  isNotNull: true,
                  type: "INTEGER"
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
                  isNotNull: true,
                  type: "INTEGER"
                ),
                [1]: TableInfo(
                  defaultValue: nil,
                  isPrimaryKey: true,
                  name: "id",
                  isNotNull: true,
                  type: "INTEGER"
                )
              ]
            ),
            [10]: RecordType(
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
                  isNotNull: true,
                  type: "INTEGER"
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
                  isNotNull: true,
                  type: "INTEGER"
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
            )
          ]
          """#
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func tearDownErasesMetadata() async throws {
        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Personal") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        try await syncEngine.metadatabase.read { db in
          try #expect(SyncMetadata.all.fetchCount(db) > 0)
          try #expect(RecordType.all.fetchCount(db) > 0)
          try #expect(StateSerialization.all.fetchCount(db) == 0)
        }

        try syncEngine.tearDownSyncEngine()
        try await syncEngine.metadatabase.read { db in
          try #expect(SyncMetadata.all.fetchCount(db) == 0)
          try #expect(RecordType.all.fetchCount(db) == 0)
          try #expect(StateSerialization.all.fetchCount(db) == 0)
        }
        try syncEngine.setUpSyncEngine()
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func reSetUp() async throws {
        let recordTypes = try await syncEngine.metadatabase.read { db in
          try RecordType.all.fetchAll(db)
        }
        syncEngine.stop()
        try syncEngine.tearDownSyncEngine()
        try syncEngine.setUpSyncEngine()
        try await syncEngine.start()
        let recordTypesAfterReSetup = try await syncEngine.metadatabase.read { db in
          try RecordType.all.fetchAll(db)
        }
        expectNoDifference(recordTypes, recordTypesAfterReSetup)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func migration() async throws {
        let recordTypes = try await syncEngine.metadatabase.read { db in
          try RecordType.order(by: \.tableName).fetchAll(db)
        }
        syncEngine.stop()
        try syncEngine.tearDownSyncEngine()
        try await userDatabase.userWrite { db in
          try #sql(
            """
            ALTER TABLE "reminders" ADD COLUMN "newFeature" INTEGER NOT NULL 
            """
          )
          .execute(db)
        }
        try syncEngine.setUpSyncEngine()
        try await syncEngine.start()

        let recordTypesAfterMigration = try await syncEngine.metadatabase.read { db in
          try RecordType.order(by: \.tableName).fetchAll(db)
        }
        let remindersTableIndex = try #require(
          recordTypesAfterMigration.firstIndex { $0.tableName == Reminder.tableName }
        )
        #expect(
          recordTypes[0..<remindersTableIndex] == recordTypesAfterMigration[0..<remindersTableIndex]
        )
        #expect(
          recordTypes[(remindersTableIndex + 1)...]
            == recordTypesAfterMigration[(remindersTableIndex + 1)...]
        )

        assertInlineSnapshot(of: recordTypesAfterMigration[remindersTableIndex], as: .customDump) {
          #"""
          RecordType(
            tableName: "reminders",
            schema: """
              CREATE TABLE "reminders" (
                "id" INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                "dueDate" TEXT,
                "isCompleted" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0,
                "priority" INTEGER,
                "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
                "remindersListID" INTEGER NOT NULL, "newFeature" INTEGER NOT NULL,
                
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
                type: "INTEGER"
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
                name: "newFeature",
                isNotNull: true,
                type: "INTEGER"
              ),
              [4]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "priority",
                isNotNull: false,
                type: "INTEGER"
              ),
              [5]: TableInfo(
                defaultValue: nil,
                isPrimaryKey: false,
                name: "remindersListID",
                isNotNull: true,
                type: "INTEGER"
              ),
              [6]: TableInfo(
                defaultValue: "\'\'",
                isPrimaryKey: false,
                name: "title",
                isNotNull: true,
                type: "TEXT"
              )
            ]
          )
          """#
        }
      }

      // * Stop sync engine
      // * Migrate to add new table
      // * Create new sync engine but forget to add table
      // * Create new sync engine but this time add the table
      // * Confirm that new table records are uploaded to CloudKit
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func migrationAddTableForgetToAddToSyncEngine() async throws {
        let recordTypes = try await syncEngine.metadatabase.read { db in
          try RecordType.order(by: \.tableName).fetchAll(db)
        }
        syncEngine.stop()
        try syncEngine.tearDownSyncEngine()

        try await userDatabase.userWrite { db in
          try #sql(
            """
            CREATE TABLE "foos" (
              "id" INTEGER PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())
            ) 
            """
          )
          .execute(db)
          try Foo
            .insert { Foo(id: 1) }
            .execute(db)
        }

        // Relaunch sync engine but forget to add new table to sync engine.
        do {
          let relaunchedSyncEngine = try await SyncEngine(
            container: syncEngine.container,
            userDatabase: syncEngine.userDatabase,
            tables: syncEngine.tables,
            privateTables: syncEngine.privateTables
          )
          let recordTypesAfterMigration = try await syncEngine.metadatabase.read { db in
            try RecordType.order(by: \.tableName).fetchAll(db)
          }
          expectNoDifference(recordTypesAfterMigration, recordTypes)
          relaunchedSyncEngine.stop()
          try relaunchedSyncEngine.tearDownSyncEngine()
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

        // Relaunch sync engine and remember this time to add new table to sync engine.
        do {
          let relaunchedSyncEngine = try await SyncEngine(
            container: syncEngine.container,
            userDatabase: syncEngine.userDatabase,
            tables: syncEngine.tables + [SynchronizedTable(for: Foo.self)],
            privateTables: syncEngine.privateTables
          )
          try await relaunchedSyncEngine.processPendingRecordZoneChanges(scope: .private)
          assertInlineSnapshot(of: container, as: .customDump) {
            """
            MockCloudContainer(
              privateCloudDatabase: MockCloudDatabase(
                databaseScope: .private,
                storage: [
                  [0]: CKRecord(
                    recordID: CKRecord.ID(1:foos/zone/__defaultOwner__),
                    recordType: "foos",
                    parent: nil,
                    share: nil,
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
        }
      }
    }
  }

  @Table
  private struct Foo {
    let id: Int
  }
#endif
