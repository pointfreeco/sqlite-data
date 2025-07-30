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
  @Suite
  final class FetchRecordZoneChangeTests: BaseCloudKitTests, @unchecked Sendable {
    @Test func saveExtraFieldsToSyncMetadata() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let reminderRecord = try syncEngine.private.database
        .record(for: Reminder.recordID(for: 1))
      reminderRecord.setValue("Hello world! 🌎🌎🌎", forKey: "newField", at: now)

      try await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord]).notify()

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
              id: 1,
              isCompleted: 0,
              newField: "Hello world! 🌎🌎🌎",
              remindersListID: 1,
              title: "Get milk"
            ),
            [1]: CKRecord(
              recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
              recordType: "remindersLists",
              parent: nil,
              share: nil,
              id: 1,
              title: "Personal"
            )
          ]
          """
        }
      }

      try await withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.isCompleted.toggle() }.execute(db)
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

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
                id: 1,
                isCompleted: 1,
                newField: "Hello world! 🌎🌎🌎",
                remindersListID: 1,
                title: "Get milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                title: "Personal"
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
          RemindersList(id: 1, title: "Personal")
          RemindersList(id: 2, title: "Business")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      try await withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        let reminderRecord = try syncEngine.private.database
          .record(for: Reminder.recordID(for: 1))
        reminderRecord.setValue("2", forKey: "remindersListID", at: now)
        reminderRecord.parent = CKRecord.Reference(
          recordID: RemindersList.recordID(for: 2),
          action: .none
        )

        try await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord]).notify()
      }

      assertInlineSnapshot(
        of: syncEngine.private.database
          .storage[syncEngine.defaultZone.zoneID]?[Reminder.recordID(for: 1)],
        as: .customDump
      ) {
        """
        CKRecord(
          recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
          recordType: "reminders",
          parent: CKReference(recordID: CKRecord.ID(2:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
          share: nil,
          id: 1,
          isCompleted: 0,
          remindersListID: "2",
          title: "Get milk"
        )
        """
      }

      try await userDatabase.read { db in
        let metadata = try #require(
          try Reminder.metadata(for: 1).fetchOne(db)
        )
        #expect(metadata.parentRecordName == RemindersList.recordName(for: 2))
        let reminder = try #require(try Reminder.find(1).fetchOne(db))
        #expect(reminder == Reminder(id: 1, title: "Get milk", remindersListID: 2))
      }

      try await userDatabase.userWrite { db in
        try Reminder.find(1).update { $0.isCompleted.toggle() }.execute(db)
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      assertInlineSnapshot(
        of: syncEngine.private.database.storage[syncEngine.defaultZone.zoneID]?[
          Reminder.recordID(for: 1)
        ],
        as: .customDump
      ) {
        """
        CKRecord(
          recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
          recordType: "reminders",
          parent: CKReference(recordID: CKRecord.ID(2:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
          share: nil,
          id: 1,
          isCompleted: 0,
          remindersListID: "2",
          title: "Get milk"
        )
        """
      }

      try await userDatabase.read { db in
        let metadata = try #require(
          try Reminder.metadata(for: 1).fetchOne(db)
        )
        #expect(metadata.parentRecordName == RemindersList.recordName(for: 2))
        let reminder = try #require(try Reminder.find(1).fetchOne(db))
        #expect(
          reminder
            == Reminder(
              id: 1,
              isCompleted: true,
              title: "Get milk",
              remindersListID: 2
            )
        )
      }
    }

    @Test func receiveNewRecordFromCloudKit() async throws {
      let remindersListRecord = CKRecord.init(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: 1)
      )
      remindersListRecord.setValue("1", forKey: "id", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)

      try await syncEngine.modifyRecords(scope: .private, saving: [remindersListRecord]).notify()

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
                id: "1",
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

      try await userDatabase.read { db in
        let metadata = try #require(
          try RemindersList.metadata(for: 1).fetchOne(db)
        )
        #expect(metadata.recordName == RemindersList.recordName(for: 1))
        let remindersList = try #require(try RemindersList.find(1).fetchOne(db))
        #expect(remindersList == RemindersList(id: 1, title: "Personal"))
      }

      try await withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try await userDatabase.userWrite { db in
          try RemindersList.find(1).update { $0.title = "My stuff" }.execute(db)
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
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

      try await userDatabase.read { db in
        let remindersList = try #require(try RemindersList.find(1).fetchOne(db))
        #expect(remindersList == RemindersList(id: 1, title: "My stuff"))
      }
    }

    @Test func receiveNewRecordFromCloudKit_ChildBeforeParent() async throws {
      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: 1)
      )
      remindersListRecord.setValue("1", forKey: "id", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)

      let reminderRecord = CKRecord(
        recordType: Reminder.tableName,
        recordID: Reminder.recordID(for: 1)
      )
      reminderRecord.setValue("1", forKey: "id", at: now)
      reminderRecord.setValue("Get milk", forKey: "title", at: now)
      reminderRecord.setValue("1", forKey: "remindersListID", at: now)
      reminderRecord.parent = CKRecord.Reference(
        recordID: RemindersList.recordID(for: 1),
        action: .none
      )

      let remindersListModification = try syncEngine.modifyRecords(
        scope: .private,
        saving: [remindersListRecord]
      )
      try await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord]).notify()

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
                id: "1",
                remindersListID: "1",
                title: "Get milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "1",
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

      await remindersListModification.notify()

      try await userDatabase.read { db in
        let reminderMetadata = try #require(
          try Reminder.metadata(for: 1).fetchOne(db)
        )
        #expect(reminderMetadata.recordName == Reminder.recordName(for: 1))
        #expect(reminderMetadata.parentRecordName == RemindersList.recordName(for: 1))

        let remindersListMetadata = try #require(
          try RemindersList.metadata(for: 1).fetchOne(db)
        )
        #expect(remindersListMetadata.recordName == RemindersList.recordName(for: 1))
        #expect(remindersListMetadata.parentRecordName == nil)

        let reminder = try #require(try Reminder.find(1).fetchOne(db))
        #expect(reminder == Reminder(id: 1, title: "Get milk", remindersListID: 1))

        let remindersList = try #require(try RemindersList.find(1).fetchOne(db))
        #expect(remindersList == RemindersList(id: 1, title: "Personal"))
      }

      try await withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.title = "Buy milk" }.execute(db)
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      }

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
                title: "Buy milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "1",
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

      try await userDatabase.read { db in
        let reminder = try #require(try Reminder.find(1).fetchOne(db))
        #expect(reminder == Reminder(id: 1, title: "Buy milk", remindersListID: 1))
      }
    }

    @Test func deleteMultipleRecords() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 3, title: "Get milk", remindersListID: 1)
          RemindersList(id: 2, title: "Business")
          Reminder(id: 4, title: "Call accountant", remindersListID: 2)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      try await syncEngine.modifyRecords(
        scope: .private,
        deleting: [
          RemindersList.recordID(for: 1),
          RemindersList.recordID(for: 2),
          Reminder.recordID(for: 3),
          Reminder.recordID(for: 4),
        ]
      )
      .notify()

      try await userDatabase.read { db in
        try #expect(Reminder.all.fetchCount(db) == 0)
        try #expect(RemindersList.all.fetchCount(db) == 0)
      }
    }
  }
}
