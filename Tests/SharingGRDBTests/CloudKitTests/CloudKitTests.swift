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
      let zones = try database.userWrite { db in
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
                "title" TEXT NOT NULL DEFAULT ''
              ) STRICT
              """
          ),
          [1]: RecordType(
            tableName: "remindersListPrivates",
            schema: """
              CREATE TABLE "remindersListPrivates" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "position" INTEGER NOT NULL DEFAULT 0,
                "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE
              ) STRICT
              """
          ),
          [2]: RecordType(
            tableName: "reminders",
            schema: """
              CREATE TABLE "reminders" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "isCompleted" INTEGER NOT NULL DEFAULT 0,
                "title" TEXT NOT NULL DEFAULT '',
                "remindersListID" TEXT NOT NULL, 
                
                FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
              ) STRICT
              """
          ),
          [3]: RecordType(
            tableName: "tags",
            schema: """
              CREATE TABLE "tags" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "title" TEXT NOT NULL DEFAULT ''
              ) STRICT
              """
          ),
          [4]: RecordType(
            tableName: "reminderTags",
            schema: """
              CREATE TABLE "reminderTags" (
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "reminderID" TEXT NOT NULL REFERENCES "reminders"("id") ON DELETE CASCADE,
                "tagID" TEXT NOT NULL REFERENCES "tags"("id") ON DELETE CASCADE
              ) STRICT
              """
          ),
          [5]: RecordType(
            tableName: "parents",
            schema: """
              CREATE TABLE "parents"(
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid())
              ) STRICT
              """
          ),
          [6]: RecordType(
            tableName: "childWithOnDeleteRestricts",
            schema: """
              CREATE TABLE "childWithOnDeleteRestricts"(
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "parentID" TEXT NOT NULL REFERENCES "parents"("id") ON DELETE RESTRICT ON UPDATE RESTRICT
              ) STRICT
              """
          ),
          [7]: RecordType(
            tableName: "childWithOnDeleteSetNulls",
            schema: """
              CREATE TABLE "childWithOnDeleteSetNulls"(
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
                "parentID" TEXT REFERENCES "parents"("id") ON DELETE SET NULL ON UPDATE SET NULL
              ) STRICT
              """
          ),
          [8]: RecordType(
            tableName: "childWithOnDeleteSetDefaults",
            schema: """
              CREATE TABLE "childWithOnDeleteSetDefaults"(
                "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT '00000000-0000-0000-0000-000000000000',
                "parentID" TEXT REFERENCES "parents"("id") ON DELETE SET DEFAULT ON UPDATE SET DEFAULT
              ) STRICT
              """
          )
        ]
        """#
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func tearDown() async throws {
      try await database.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
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
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
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

      try await database.userWrite { db in
        let metadataCount = try SyncMetadata.count().fetchOne(db) ?? 0
        #expect(metadataCount == 1)
      }
      try await syncEngine.tearDownSyncEngine()
      try await self.database.userWrite { db in
        let metadataCount = try SyncMetadata.count().fetchOne(db) ?? 0
        #expect(metadataCount == 0)
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func tearDownAndReSetUp() async throws {
      try await syncEngine.tearDownSyncEngine()
      try await syncEngine.setUpSyncEngine()

      try await database.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
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
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
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
        try await database.userRead { db in
          try SyncMetadata.find(RemindersList.recordName(for: UUID(1))).fetchOne(db)
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
        of: try { try database.userWrite { try query.fetchAll($0) } }(),
        as: .customDump
      ) {
        """
        [
          [0]: "sqlitedata_icloud_datetime",
          [1]: "sqlitedata_icloud_didupdate",
          [2]: "sqlitedata_icloud_isupdatingwithserverrecord",
          [3]: "sqlitedata_icloud_diddelete"
        ]
        """
      }
      try await syncEngine.tearDownSyncEngine()

      assertInlineSnapshot(
        of: try { try database.userWrite { try query.fetchAll($0) } }(),
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
      try await database.userWrite { db in
        try RemindersList
          .insert { RemindersList(id: UUID(1), title: "Personal") }
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
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
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

      try await database.userWrite { db in
        try RemindersList
          .find(UUID(1))
          .update { $0.title = "Work" }
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
                id: "00000000-0000-0000-0000-000000000001",
                title: "Work",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
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

      try await database.userWrite { db in
        try RemindersList
          .find(UUID(1))
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
      try await database.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
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
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
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
        try await database.userRead { db in
          try SyncMetadata
            .find(RemindersList.recordName(for: UUID(1)))
            .select(\.userModificationDate)
            .fetchOne(db) ?? nil
        }
      )

      let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: UUID(1)))
      record.encryptedValues["title"] = "Work"
      let serverModificationDate = userModificationDate.addingTimeInterval(60)
      record.userModificationDate = serverModificationDate
      _ = await syncEngine.modifyRecords(scope: .private, saving: [record])

      expectNoDifference(
        try { try database.userRead { db in try RemindersList.find(UUID(1)).fetchOne(db) } }(),
        RemindersList(id: UUID(1), title: "Work")
      )

      let metadata = try #require(
        try await database.userRead { db in
          try SyncMetadata
            .find(RemindersList.recordName(for: UUID(1)))
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
                id: "00000000-0000-0000-0000-000000000001",
                title: "Work",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:32:30.000Z)
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
      try await database.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
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
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
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
        try await database.userWrite { db in
          try SyncMetadata
            .find(RemindersList.recordName(for: UUID(1)))
            .select(\.userModificationDate)
            .fetchOne(db) ?? nil
        }
      )

      let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: UUID(1)))
      record.encryptedValues["title"] = "Work"
      let serverModificationDate = userModificationDate.addingTimeInterval(-60.0)
      record.userModificationDate = serverModificationDate
      // NB: Manually setting '_recordChangeTag' simulates another devices saving a record.
      record._recordChangeTag = UUID().uuidString
      _ = await syncEngine.modifyRecords(scope: .private, saving: [record])

      expectNoDifference(
        try { try database.userRead { db in try RemindersList.find(UUID(1)).fetchOne(db) } }(),
        RemindersList(id: UUID(1), title: "Personal")
      )

      let metadata = try #require(
        try await database.userWrite { db in
          try SyncMetadata
            .find(RemindersList.recordName(for: UUID(1)))
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
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
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
      try await database.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
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
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
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

      let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: UUID(1)))
      _ = await syncEngine.modifyRecords(scope: .private, deleting: [record.recordID])

      #expect(
        try await database.userRead { db in try RemindersList.find(UUID(1)).fetchAll(db) }
          == []
      )
      let metadata = try await database.userWrite { db in
        try SyncMetadata
          .find(RemindersList.recordName(for: UUID(1)))
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
      try await database.userWrite { db in
        try db.seed {
          Tag(id: UUID(1), title: "")
          Tag(id: UUID(2), title: "")
        }
      }
      for _ in 1...100 {
        try await database.userWrite { db in
          try db.seed {
            RemindersList(id: UUID(1), title: "Personal")
            RemindersListPrivate(id: UUID(1), position: 1, remindersListID: UUID(1))
            Reminder(id: UUID(1), title: "", remindersListID: UUID(1))
            Reminder(id: UUID(2), title: "", remindersListID: UUID(1))
            Reminder(id: UUID(3), title: "", remindersListID: UUID(1))
            Reminder(id: UUID(4), title: "", remindersListID: UUID(1))
            ReminderTag(id: UUID(1), reminderID: UUID(1), tagID: UUID(1))
            ReminderTag(id: UUID(2), reminderID: UUID(2), tagID: UUID(1))
            ReminderTag(id: UUID(3), reminderID: UUID(3), tagID: UUID(1))
            ReminderTag(id: UUID(4), reminderID: UUID(4), tagID: UUID(1))
            ReminderTag(id: UUID(5), reminderID: UUID(1), tagID: UUID(2))
            ReminderTag(id: UUID(6), reminderID: UUID(2), tagID: UUID(2))
            ReminderTag(id: UUID(7), reminderID: UUID(3), tagID: UUID(2))
            ReminderTag(id: UUID(8), reminderID: UUID(4), tagID: UUID(2))
          }
        }

        await syncEngine.processBatch()

        try await database.userWrite { db in
          try RemindersList.find(UUID(1)).delete().execute(db)
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
                  id: "00000000-0000-0000-0000-000000000001",
                  title: "",
                  sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(2:tags/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                  recordType: "tags",
                  parent: nil,
                  share: nil,
                  id: "00000000-0000-0000-0000-000000000002",
                  title: "",
                  sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
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
