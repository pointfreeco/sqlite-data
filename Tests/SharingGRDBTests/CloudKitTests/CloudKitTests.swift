import CloudKit
import ConcurrencyExtras
import CustomDump
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class CloudKitTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func tearDown() async throws {
      try await database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
        }
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1)))
      ])
      
      try await database.write { db in
        let metadataCount = try SyncMetadata.count().fetchOne(db) ?? 0
        #expect(metadataCount == 1)
      }
      try await syncEngine.tearDownSyncEngine()
      try await self.database.write { db in
        let metadataCount = try SyncMetadata.count().fetchOne(db) ?? 0
        #expect(metadataCount == 0)
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func tearDownAndReSetUp() async throws {
      try await syncEngine.tearDownSyncEngine()
      try await syncEngine.setUpSyncEngine()
      privateSyncEngine.assertFetchChangesScopes([.all])
      sharedSyncEngine.assertFetchChangesScopes([.all])

      try await database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
        }
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1)))
      ])


      let record = CKRecord(
        recordType: "remindersLists",
        recordID: RemindersList.recordID(for: UUID(1))
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
        of: try { try database.write { try query.fetchAll($0) } }(),
        as: .customDump
      ) {
        """
        [
          [0]: "sqlitedata_icloud_didupdate",
          [1]: "sqlitedata_icloud_isupdatingwithserverrecord",
          [2]: "sqlitedata_icloud_diddelete"
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
          .insert { RemindersList(id: UUID(1), title: "Personal") }
          .execute(db)
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1)))
      ])
      try database.write { db in
        try RemindersList
          .find(UUID(1))
          .update { $0.title = "Work" }
          .execute(db)
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1)))
      ])
      try database.write { db in
        try RemindersList
          .find(UUID(1))
          .delete()
          .execute(db)
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .deleteRecord(RemindersList.recordID(for: UUID(1)))
      ])
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func remoteServerRecordUpdate() async throws {
      try await database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
        }
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1)))
      ])

      let record = CKRecord(
        recordType: "remindersLists",
        recordID: RemindersList.recordID(for: UUID(1))
      )
      let userModificationDate = try #require(
        try await database.write { db in
          try SyncMetadata
            .find(RemindersList.recordName(for: UUID(1)))
            .select(\.userModificationDate)
            .fetchOne(db) ?? nil
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
          try SyncMetadata
            .find(RemindersList.recordName(for: UUID(1)))
            .fetchOne(db)
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
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1)))
      ])
      let record = CKRecord(
        recordType: "remindersLists",
        recordID: RemindersList.recordID(for: UUID(1))
      )
      let userModificationDate = try #require(
        try await database.write { db in
          try SyncMetadata
            .find(RemindersList.recordName(for: UUID(1)))
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
          try SyncMetadata
            .find(RemindersList.recordName(for: UUID(1)))
            .fetchOne(db)
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
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1)))
      ])

      let record = CKRecord(
        recordType: "remindersLists",
        recordID: RemindersList.recordID(for: UUID(1))
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
        try SyncMetadata
          .find(RemindersList.recordName(for: UUID(1)))
          .fetchOne(db)
      }
      #expect(metadata == nil)
    }
  }

  // TODO: Test what happens when we delete locally and then an edit comes in from the server
}


