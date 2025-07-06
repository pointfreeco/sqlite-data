import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import OrderedCollections
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  @Suite(.printTimestamps)
  final class FetchRecordZoneChangeTests: BaseCloudKitTests, @unchecked Sendable {
    @Dependency(\.date.now) var now

    @Test func saveExtraFieldsToSyncMetadata() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(1), title: "Get milk", remindersListID: UUID(1))
        }
      }
      await syncEngine.processBatch()

      let reminderRecord = try syncEngine.private.database
        .record(for: Reminder.recordID(for: UUID(1)))
      reminderRecord.setValue("Hello world! 🌎🌎🌎", forKey: "newField", at: now)

      await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])

      do {
        let lastKnownServerRecords = try await syncEngine.metadatabase.read { db in
          try SyncMetadata
            .order(by: \.recordName)
            .select(\._lastKnownServerRecordAllFields)
            .fetchAll(db)
        }
        assertInlineSnapshot(of: lastKnownServerRecords, as: .customDump) {
          """
          [
            [0]: CKRecord(
              recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
              recordType: "reminders",
              parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
              share: nil,
              id: "00000000-0000-0000-0000-000000000001",
              id🗓️: 0,
              isCompleted: 0,
              isCompleted🗓️: 0,
              newField: "Hello world! 🌎🌎🌎",
              newField🗓️: 0,
              remindersListID: "00000000-0000-0000-0000-000000000001",
              remindersListID🗓️: 0,
              title: "Get milk",
              title🗓️: 0,
              🗓️: 0
            ),
            [1]: CKRecord(
              recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
              recordType: "remindersLists",
              parent: nil,
              share: nil,
              id: "00000000-0000-0000-0000-000000000001",
              id🗓️: 0,
              title: "Personal",
              title🗓️: 0,
              🗓️: 0
            )
          ]
          """
        }
      }

      try await withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(UUID(1)).update { $0.isCompleted.toggle() }.execute(db)
        }

        await syncEngine.processBatch()

        do {
          let lastKnownServerRecords = try await syncEngine.metadatabase.read { db in
            try SyncMetadata
              .order(by: \.recordName)
              .select(\._lastKnownServerRecordAllFields)
              .fetchAll(db)
          }
          assertInlineSnapshot(of: lastKnownServerRecords, as: .customDump) {
            """
            [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                id🗓️: 0,
                isCompleted: 1,
                isCompleted🗓️: 1,
                newField: "Hello world! 🌎🌎🌎",
                newField🗓️: 0,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                remindersListID🗓️: 0,
                title: "Get milk",
                title🗓️: 0,
                🗓️: 1
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                id🗓️: 0,
                title: "Personal",
                title🗓️: 0,
                🗓️: 0
              )
            ]
            """
          }
        }
      }
    }

    @Test func remoteChangeParentRelationship() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          RemindersList(id: UUID(2), title: "Business")
          Reminder(id: UUID(1), title: "Get milk", remindersListID: UUID(1))
        }
      }
      await syncEngine.processBatch()

      try await withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        let reminderRecord = try syncEngine.private.database
          .record(for: Reminder.recordID(for: UUID(1)))
        reminderRecord.setValue(UUID(2).uuidString.lowercased(), forKey: "remindersListID", at: now)
        reminderRecord.parent = CKRecord.Reference(
          recordID: RemindersList.recordID(for: UUID(2)),
          action: .none
        )

        await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])
      }

      assertInlineSnapshot(
        of: syncEngine.private.database.storage[Reminder.recordID(for: UUID(1))],
        as: .customDump
      ) {
        """
        CKRecord(
          recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
          recordType: "reminders",
          parent: CKReference(recordID: CKRecord.ID(2:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
          share: nil,
          id: "00000000-0000-0000-0000-000000000001",
          id🗓️: 0,
          isCompleted: 0,
          isCompleted🗓️: 0,
          remindersListID: "00000000-0000-0000-0000-000000000002",
          remindersListID🗓️: 1,
          title: "Get milk",
          title🗓️: 0,
          🗓️: 0
        )
        """
      }

      try {
        try userDatabase.read { db in
          let metadata = try #require(
            try SyncMetadata.find(Reminder.recordName(for: UUID(1))).fetchOne(db)
          )
          #expect(metadata.parentRecordName == RemindersList.recordName(for: UUID(2)))
          let reminder = try #require(try Reminder.find(UUID(1)).fetchOne(db))
          #expect(reminder == Reminder(id: UUID(1), title: "Get milk", remindersListID: UUID(2)))
        }
      }()

      try await userDatabase.userWrite { db in
        try Reminder.find(UUID(1)).update { $0.isCompleted.toggle() }.execute(db)
      }

      await syncEngine.processBatch()

      assertInlineSnapshot(
        of: syncEngine.private.database.storage[Reminder.recordID(for: UUID(1))],
        as: .customDump
      ) {
        """
        CKRecord(
          recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
          recordType: "reminders",
          parent: CKReference(recordID: CKRecord.ID(2:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
          share: nil,
          id: "00000000-0000-0000-0000-000000000001",
          id🗓️: 0,
          isCompleted: 0,
          isCompleted🗓️: 0,
          remindersListID: "00000000-0000-0000-0000-000000000002",
          remindersListID🗓️: 1,
          title: "Get milk",
          title🗓️: 0,
          🗓️: 0
        )
        """
      }

      try {
        try userDatabase.read { db in
          let metadata = try #require(
            try SyncMetadata.find(Reminder.recordName(for: UUID(1))).fetchOne(db)
          )
          #expect(metadata.parentRecordName == RemindersList.recordName(for: UUID(2)))
          let reminder = try #require(try Reminder.find(UUID(1)).fetchOne(db))
          #expect(
            reminder == Reminder(
              id: UUID(1),
              isCompleted: true,
              title: "Get milk",
              remindersListID: UUID(2)
            )
          )
        }
      }()
    }

    @Test func receiveNewRecordFromCloudKit() async throws {
      let remindersListRecord = CKRecord.init(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: UUID(1))
      )
      remindersListRecord.setValue(UUID(1).uuidString.lowercased(), forKey: "id", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)
      remindersListRecord.userModificationDate = now

      await syncEngine.modifyRecords(scope: .private, saving: [remindersListRecord])

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
                id🗓️: 0,
                title: "Personal",
                title🗓️: 0,
                🗓️: 0
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

      try {
        try userDatabase.read { db in
          let metadata = try #require(
            try SyncMetadata.find(RemindersList.recordName(for: UUID(1))).fetchOne(db)
          )
          #expect(metadata.recordName == RemindersList.recordName(for: UUID(1)))
          let remindersList = try #require(try RemindersList.find(UUID(1)).fetchOne(db))
          #expect(remindersList == RemindersList(id: UUID(1), title: "Personal"))
        }
      }()

      try await withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try await userDatabase.userWrite { db in
          try RemindersList.find(UUID(1)).update { $0.title = "My stuff" }.execute(db)
        }

        await syncEngine.processBatch()
      }

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
                id🗓️: 0,
                title: "My stuff",
                title🗓️: 1,
                🗓️: 1
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

      try {
        try userDatabase.read { db in
          let remindersList = try #require(try RemindersList.find(UUID(1)).fetchOne(db))
          #expect(remindersList == RemindersList(id: UUID(1), title: "My stuff"))
        }
      }()
    }
  }
}
