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
      let recordTypes = try await userDatabase.userRead { db in
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
      try syncEngine.tearDownSyncEngine()
      try await userDatabase.userRead { db in
        try #expect(RecordType.all.fetchAll(db) == [])
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func resetUp() async throws {
      let recordTypes = try await userDatabase.userRead { db in
        try RecordType.all.fetchAll(db)
      }
      syncEngine.stop()
      try syncEngine.tearDownSyncEngine()
      try syncEngine.setUpSyncEngine()
      try await syncEngine.start()
      let recordTypesAfterReSetup = try await userDatabase.userRead { db in
        try RecordType.all.fetchAll(db)
      }
      expectNoDifference(recordTypes, recordTypesAfterReSetup)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func migration() async throws {
      let recordTypes = try await userDatabase.userRead { db in
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

      let recordTypesAfterMigration = try await userDatabase.userRead { db in
        try RecordType.order(by: \.tableName).fetchAll(db)
      }
      let remindersTableIndex = try #require(
        recordTypesAfterMigration.firstIndex { $0.tableName == Reminder.tableName }
      )
      #expect(recordTypes[0..<remindersTableIndex] == recordTypesAfterMigration[0..<remindersTableIndex])
      #expect(recordTypes[(remindersTableIndex+1)...] == recordTypesAfterMigration[(remindersTableIndex+1)...])

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
              name: "newFeature",
              notNull: true,
              type: "INTEGER"
            ),
            [4]: TableInfo(
              defaultValue: nil,
              isPrimaryKey: false,
              name: "priority",
              notNull: false,
              type: "INTEGER"
            ),
            [5]: TableInfo(
              defaultValue: nil,
              isPrimaryKey: false,
              name: "remindersListID",
              notNull: true,
              type: "INTEGER"
            ),
            [6]: TableInfo(
              defaultValue: "\'\'",
              isPrimaryKey: false,
              name: "title",
              notNull: true,
              type: "TEXT"
            )
          ]
        )
        """#
      }
    }
  }
}
