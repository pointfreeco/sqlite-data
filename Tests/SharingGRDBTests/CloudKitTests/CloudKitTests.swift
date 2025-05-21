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
        try Zone.all.fetchAll(db)
      }
      assertInlineSnapshot(of: zones, as: .customDump) {
        #"""
        [
          [0]: Zone(
            zoneName: "remindersLists",
            schema: """
              CREATE TABLE "remindersLists" (
                "id" TEXT PRIMARY KEY DEFAULT (uuid()),
                "title" TEXT NOT NULL
              ) STRICT
              """
          ),
          [1]: Zone(
            zoneName: "reminders",
            schema: """
              CREATE TABLE "reminders" (
                "id" TEXT PRIMARY KEY DEFAULT (uuid()),
                "title" TEXT NOT NULL,
                "parentReminderID" TEXT REFERENCES "reminders"("id") ON DELETE SET NULL,
                "remindersListID" TEXT NOT NULL REFERENCES "remindersLists"("id") ON DELETE CASCADE ON UPDATE CASCADE
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
      underlyingSyncEngine.assertFetchChangesScopes([
        .zoneIDs([
          CKRecordZone.ID(RemindersList.self),
          CKRecordZone.ID(Reminder.self),
        ])
      ])

      try await database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
        }
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self))
      ])

      let record = CKRecord(
        recordType: "remindersLists",
        recordID: CKRecord.ID(UUID(1), in: RemindersList.self)
      )
      await syncEngine.handleFetchedRecordZoneChanges(
        modifications: [record],
        deletions: []
      )
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
        .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self))
      ])
      try database.write { db in
        try RemindersList
          .find(UUID(1))
          .update { $0.title = "Work" }
          .execute(db)
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self))
      ])
      try database.write { db in
        try RemindersList
          .find(UUID(1))
          .delete()
          .execute(db)
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .deleteRecord(CKRecord.ID(UUID(1), in: RemindersList.self))
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
        .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self))
      ])

      let record = CKRecord(
        recordType: "remindersLists",
        recordID: CKRecord.ID(UUID(1), in: RemindersList.self)
      )
      let userModificationDate = try #require(
        try await database.write { db in
          try Metadata.find(recordID: record.recordID).select(\.userModificationDate).fetchOne(db)!
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
      #expect(metadata.userModificationDate == serverModificationDate)
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func remoteServerRecordUpdateWithOldRecord() async throws {
      try await database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
        }
      }
      underlyingSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self))
      ])
      let record = CKRecord(
        recordType: "remindersLists",
        recordID: CKRecord.ID(UUID(1), in: RemindersList.self)
      )
      let userModificationDate = try #require(
        try await database.write { db in
          try Metadata.find(recordID: record.recordID).select(\.userModificationDate).fetchOne(db)!
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
        .saveRecord(CKRecord.ID(UUID(1), in: RemindersList.self))
      ])

      let record = CKRecord(
        recordType: "remindersLists",
        recordID: CKRecord.ID(UUID(1), in: RemindersList.self)
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
}
