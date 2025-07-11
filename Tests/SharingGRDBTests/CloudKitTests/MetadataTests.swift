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
  final class MetadataTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func parentRecordName() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          RemindersList(id: UUID(2), title: "Work")
          Reminder(id: UUID(1), title: "Groceries", remindersListID: UUID(1))
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
                recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                isCompleted: 0,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                title: "Groceries"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal"
              ),
              [2]: CKRecord(
                recordID: CKRecord.ID(2:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000002",
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

      try await userDatabase.userRead { db in
        let reminderMetadata = try #require(
          try SyncMetadata
            .where { $0.recordName.eq(Reminder.recordName(for: UUID(1))) }
            .fetchOne(db)
        )
        #expect(reminderMetadata.parentRecordName == RemindersList.recordName(for: UUID(1)))
      }

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        _ = try {
          try userDatabase.userWrite { db in
            try Reminder.find(UUID(1))
              .update { $0.remindersListID = UUID(2) }
              .execute(db)
            let reminderMetadata = try #require(
              try SyncMetadata
                .where { $0.recordName.eq(Reminder.recordName(for: UUID(1))) }
                .fetchOne(db)
            )
            #expect(reminderMetadata.parentRecordName == RemindersList.recordName(for: UUID(2)))
          }
        }()
      }

      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(2:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                isCompleted: 0,
                remindersListID: "00000000-0000-0000-0000-000000000002",
                title: "Groceries"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal"
              ),
              [2]: CKRecord(
                recordID: CKRecord.ID(2:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000002",
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

    @Test func noParentRecordForRecordsWithMultipleForeignKeys() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(1), title: "Groceries", remindersListID: UUID(1))
          Tag(id: UUID(1), title: "weekend")
          ReminderTag(id: UUID(1), reminderID: UUID(1), tagID: UUID(1))
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
                recordID: CKRecord.ID(1:reminderTags/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminderTags",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                reminderID: "00000000-0000-0000-0000-000000000001",
                tagID: "00000000-0000-0000-0000-000000000001"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                isCompleted: 0,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                title: "Groceries"
              ),
              [2]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal"
              ),
              [3]: CKRecord(
                recordID: CKRecord.ID(1:tags/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "tags",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
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

      let parentRecordNames = try await userDatabase.userRead { db in
        try SyncMetadata
          .where { $0.recordType != Reminder.tableName }
          .select(\.parentRecordName)
          .fetchAll(db)
      }
      #expect(parentRecordNames.allSatisfy { $0 == nil })
    }

    @Test func recordType() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(2), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(3), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(4), title: "Groceries", remindersListID: UUID(1))
        }
      }

      await syncEngine.processBatch()

      let reminderMetadata = try await userDatabase.userRead { db in
        try SyncMetadata
          .where { $0.recordType == Reminder.tableName }
          .fetchAll(db)
      }
      #expect(
        reminderMetadata.map(\.recordName) == [
          Reminder.recordName(for: UUID(2)),
          Reminder.recordName(for: UUID(3)),
          Reminder.recordName(for: UUID(4)),
        ]
      )
    }

    @Test func parentRecordType() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(2), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(3), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(4), title: "Groceries", remindersListID: UUID(1))
        }
      }

      await syncEngine.processBatch()

      try await userDatabase.userRead { db in
        let reminderMetadata =
        try SyncMetadata
          .where { $0.parentRecordType == RemindersList.tableName }
          .fetchAll(db)
        #expect(
          reminderMetadata.map(\.recordName) == [
            Reminder.recordName(for: UUID(2)),
            Reminder.recordName(for: UUID(3)),
            Reminder.recordName(for: UUID(4)),
          ]
        )
      }
    }

    @Test func parentRecordPrimaryKey() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(2), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(3), title: "Groceries", remindersListID: UUID(1))
          Reminder(id: UUID(4), title: "Groceries", remindersListID: UUID(1))
        }
      }

      await syncEngine.processBatch()

      try await userDatabase.userRead { db in
        let reminderMetadata =
        try SyncMetadata
          .where { $0.parentRecordPrimaryKey.eq(UUID(1).uuidString.lowercased()) }
          .fetchAll(db)
        #expect(
          reminderMetadata.map(\.recordName) == [
            Reminder.recordName(for: UUID(2)),
            Reminder.recordName(for: UUID(3)),
            Reminder.recordName(for: UUID(4)),
          ]
        )
      }
    }
  }
}
