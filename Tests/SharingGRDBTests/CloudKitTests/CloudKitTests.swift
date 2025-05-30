import CloudKit
import ConcurrencyExtras
import CustomDump
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  final class CloudKitTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func setUp() throws {
      let zones = try database.write { db in
        try RecordType.all.fetchAll(db)
      }
      assertInlineSnapshot(of: zones, as: .customDump) {
        #"""
        [
          [0]: RecordType(
            tableName: "remindersLists",
            schema: """
              CREATE TABLE "remindersLists" (
                "id" TEXT NOT NULL PRIMARY KEY DEFAULT (uuid()),
                "title" TEXT NOT NULL
              ) STRICT
              """
          ),
          [1]: RecordType(
            tableName: "users",
            schema: """
              CREATE TABLE "users" (
                "id" TEXT NOT NULL PRIMARY KEY DEFAULT (uuid()),
                "name" TEXT NOT NULL,
                "parentUserID" TEXT DEFAULT NULL,
              
                FOREIGN KEY("parentUserID") REFERENCES "users"("id") ON DELETE SET DEFAULT ON UPDATE CASCADE 
              ) STRICT
              """
          ),
          [2]: RecordType(
            tableName: "reminders",
            schema: """
              CREATE TABLE "reminders" (
                "id" TEXT NOT NULL PRIMARY KEY DEFAULT (uuid()),
                "assignedUserID" TEXT,
                "title" TEXT NOT NULL,
                "parentReminderID" TEXT, 
                "remindersListID" TEXT NOT NULL, 
                
                FOREIGN KEY("assignedUserID") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE,
                FOREIGN KEY("parentReminderID") REFERENCES "reminders"("id") ON DELETE RESTRICT ON UPDATE RESTRICT,
                FOREIGN KEY("remindersListID") REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
              ) STRICT
              """
          )
        ]
        """#
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func tearDownAndReSetUp() async throws {
      try await syncEngine.tearDownSyncEngine()
      try await syncEngine.setUpSyncEngine()
      // TODO: it would be nice if `setUpSyncEngine` was async
      try await Task.sleep(for: .seconds(0.1))
      underlyingSyncEngine.assertFetchChangesScopes([.all])

      try await database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
        }
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1)))
      ])


      let record = CKRecord(
        recordType: "remindersLists",
        recordID: CKRecord.ID(UUID(1))
      )
      await syncEngine.handleFetchedRecordZoneChanges(
        modifications: [record],
        deletions: []
      )
      try await Task.sleep(for: .seconds(1))
      expectNoDifference(
        try { try database.read { db in try RemindersList.find(UUID(1)).fetchOne(db) } }(),
        RemindersList(id: UUID(1), title: "Personal")
      )

      let metadata =
        try await database.write { db in
          try Metadata.find(recordID: record.recordID).fetchOne(db)
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
        of: try { try database.write { try query.fetchAll($0) } }(),
        as: .customDump
      ) {
        """
        [
          [0]: "sqlitedata_icloud_getzonename",
          [1]: "sqlitedata_icloud_didupdate",
          [2]: "sqlitedata_icloud_getownername",
          [3]: "sqlitedata_icloud_willdelete",
          [4]: "sqlitedata_icloud_isupdatingwithserverrecord"
        ]
        """
      }
      try await syncEngine.tearDownSyncEngine()

      assertInlineSnapshot(
        of: try { try database.write { try query.fetchAll($0) } }(),
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
    @Test func insertUpdateDelete() throws {
      try database.write { db in
        try RemindersList
          .insert(RemindersList(id: UUID(1), title: "Personal"))
          .execute(db)
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1)))
      ])
      try database.write { db in
        try RemindersList
          .find(UUID(1))
          .update { $0.title = "Work" }
          .execute(db)
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1)))
      ])
      try database.write { db in
        try RemindersList
          .find(UUID(1))
          .delete()
          .execute(db)
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .deleteRecord(CKRecord.ID(UUID(1)))
      ])
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func remoteServerRecordUpdate() async throws {
      try await database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
        }
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1)))
      ])

      let record = CKRecord(
        recordType: "remindersLists",
        recordID: CKRecord.ID(UUID(1))
      )
      let userModificationDate = try #require(
        try await database.write { db in
          try Metadata.find(recordID: record.recordID).select(\.userModificationDate).fetchOne(db) ?? nil
        }
      )

      // TODO: Should we omit primary key from `encryptedValues` since it already exists on recordName?
      record.encryptedValues[RemindersList.columns.id.name] = UUID(1).uuidString
      record.encryptedValues[RemindersList.columns.title.name] = "Work"
      let serverModificationDate = userModificationDate.addingTimeInterval(60)
      record.userModificationDate = serverModificationDate
      await syncEngine.handleFetchedRecordZoneChanges(modifications: [record], deletions: [])
      expectNoDifference(
        try { try database.read { db in try RemindersList.find(UUID(1)).fetchOne(db) } }(),
        RemindersList(id: UUID(1), title: "Work")
      )

      let metadata = try #require(
        try await database.write { db in
          try Metadata.find(recordID: record.recordID).fetchOne(db)
        }
      )
      // TODO: Control dates in SQLite in order to get consistent passing on float comparison
      #expect(abs(metadata.userModificationDate!.timeIntervalSince(serverModificationDate)) < 0.1)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func remoteServerRecordUpdateWithOldRecord() async throws {
      try await database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
        }
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1)))
      ])
      let record = CKRecord(
        recordType: "remindersLists",
        recordID: CKRecord.ID(UUID(1))
      )
      let userModificationDate = try #require(
        try await database.write { db in
          try Metadata
            .find(recordID: record.recordID)
            .select(\.userModificationDate)
            .fetchOne(db) ?? nil
        }
      )

      // TODO: Should we omit primary key from `encryptedValues` since it already exists on recordName?
      record.encryptedValues[RemindersList.columns.id.name] = UUID(1).uuidString
      record.encryptedValues[RemindersList.columns.title.name] = "Work"
      let serverModificationDate = userModificationDate.addingTimeInterval(-60.0)
      record.userModificationDate = serverModificationDate
      await syncEngine.handleFetchedRecordZoneChanges(modifications: [record], deletions: [])
      expectNoDifference(
        try { try database.read { db in try RemindersList.find(UUID(1)).fetchOne(db) } }(),
        RemindersList(id: UUID(1), title: "Personal")
      )

      let metadata = try #require(
        try await database.write { db in
          try Metadata.find(recordID: record.recordID).fetchOne(db)
        }
      )
      #expect(metadata.userModificationDate == userModificationDate)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func remoteServerRecordDeleted() async throws {
      try await database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
        }
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1)))
      ])

      let record = CKRecord(
        recordType: "remindersLists",
        recordID: CKRecord.ID(UUID(1))
      )
      await syncEngine.handleFetchedRecordZoneChanges(
        modifications: [],
        deletions: [(record.recordID, record.recordType)]
      )
      #expect(
        try { try database.read { db in try RemindersList.find(UUID(1)).fetchCount(db) } }()
          == 0
      )
      let metadata = try await database.write { db in
        try Metadata.find(recordID: record.recordID).fetchOne(db)
      }
      #expect(metadata == nil)
    }
  }

  // TODO: Test what happens when we delete locally and then an edit comes in from the server
}
