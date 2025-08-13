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
          RemindersList(id: 1, title: "Personal")
          RemindersList(id: 2, title: "Work")
          Reminder(id: 1, title: "Groceries", remindersListID: 1)
        }
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
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
                id: 1,
                isCompleted: 0,
                remindersListID: 1,
                title: "Groceries"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                title: "Personal"
              ),
              [2]: CKRecord(
                recordID: CKRecord.ID(2:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 2,
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
            .where { $0.recordName.eq(Reminder.recordName(for: 1)) }
            .fetchOne(db)
        )
        #expect(reminderMetadata.parentRecordName == RemindersList.recordName(for: 1))
      }

      try withDependencies {
        $0.datetime.now.addTimeInterval(60)
      } operation: {
        _ = try {
          try userDatabase.userWrite { db in
            try Reminder.find(1)
              .update { $0.remindersListID = 2 }
              .execute(db)
            let reminderMetadata = try #require(
              try SyncMetadata
                .where { $0.recordName.eq(Reminder.recordName(for: 1)) }
                .fetchOne(db)
            )
            #expect(reminderMetadata.parentRecordName == RemindersList.recordName(for: 2))
          }
        }()
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
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
                id: 1,
                isCompleted: 0,
                remindersListID: 2,
                title: "Groceries"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                title: "Personal"
              ),
              [2]: CKRecord(
                recordID: CKRecord.ID(2:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 2,
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
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, title: "Groceries", remindersListID: 1)
          Tag(title: "weekend")
          ReminderTag(id: 1, reminderID: 1, tagID: "weekend")
        }
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
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
                id: 1,
                reminderID: 1,
                tagID: "weekend"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: 1,
                isCompleted: 0,
                remindersListID: 1,
                title: "Groceries"
              ),
              [2]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                title: "Personal"
              ),
              [3]: CKRecord(
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
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 2, title: "Groceries", remindersListID: 1)
          Reminder(id: 3, title: "Groceries", remindersListID: 1)
          Reminder(id: 4, title: "Groceries", remindersListID: 1)
        }
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let reminderMetadata = try await userDatabase.userRead { db in
        try SyncMetadata
          .where { $0.recordType == Reminder.tableName }
          .fetchAll(db)
      }
      #expect(
        reminderMetadata.map(\.recordName) == [
          Reminder.recordName(for: 2),
          Reminder.recordName(for: 3),
          Reminder.recordName(for: 4),
        ]
      )
    }

    @Test func parentRecordType() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 2, title: "Groceries", remindersListID: 1)
          Reminder(id: 3, title: "Groceries", remindersListID: 1)
          Reminder(id: 4, title: "Groceries", remindersListID: 1)
        }
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      try await userDatabase.userRead { db in
        let reminderMetadata =
        try SyncMetadata
          .where { $0.parentRecordType == RemindersList.tableName }
          .fetchAll(db)
        #expect(
          reminderMetadata.map(\.recordName) == [
            Reminder.recordName(for: 2),
            Reminder.recordName(for: 3),
            Reminder.recordName(for: 4),
          ]
        )
      }
    }

    @Test func parentRecordPrimaryKey() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 2, title: "Groceries", remindersListID: 1)
          Reminder(id: 3, title: "Groceries", remindersListID: 1)
          Reminder(id: 4, title: "Groceries", remindersListID: 1)
        }
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      try await userDatabase.userRead { db in
        let reminderMetadata =
        try SyncMetadata
          .where { $0.parentRecordPrimaryKey.eq("1") }
          .fetchAll(db)
        #expect(
          reminderMetadata.map(\.recordName) == [
            Reminder.recordName(for: 2),
            Reminder.recordName(for: 3),
            Reminder.recordName(for: 4),
          ]
        )
      }
    }
  }
}
