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
  @Suite(.printTimestamps) final class MergeConflictTests: BaseCloudKitTests, @unchecked Sendable {
    @Test func merge_clientRecordUpdatedBeforeServerRecord() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "")
          Reminder(id: 1, title: "", remindersListID: 1)
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
                id🗓️: 0,
                isCompleted: 0,
                isCompleted🗓️: 0,
                remindersListID: 1,
                remindersListID🗓️: 0,
                title: "",
                title🗓️: 0,
                🗓️: 0
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                id🗓️: 0,
                title: "",
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

      let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
      let userModificationDate = now.addingTimeInterval(60)
      record.setValue("Buy milk", forKey: "title", at: userModificationDate)
      let modificationCallback = try {
        try syncEngine.modifyRecords(scope: .private, saving: [record])
      }()

      try await withDependencies {
        $0.date.now = now.addingTimeInterval(30)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.isCompleted = true }.execute(db)
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
                id🗓️: 0,
                isCompleted: 0,
                isCompleted🗓️: 0,
                remindersListID: 1,
                remindersListID🗓️: 0,
                title: "Buy milk",
                title🗓️: 60,
                🗓️: 60
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                id🗓️: 0,
                title: "",
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

      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      await modificationCallback.notify()

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
                id🗓️: 0,
                isCompleted: 1,
                isCompleted🗓️: 30,
                remindersListID: 1,
                remindersListID🗓️: 0,
                title: "Buy milk",
                title🗓️: 60,
                🗓️: 60
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                id🗓️: 0,
                title: "",
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
    }

    @Test func serverRecordUpdatedBeforeClientRecord() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "")
          Reminder(id: 1, title: "", remindersListID: 1)
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
                id🗓️: 0,
                isCompleted: 0,
                isCompleted🗓️: 0,
                remindersListID: 1,
                remindersListID🗓️: 0,
                title: "",
                title🗓️: 0,
                🗓️: 0
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                id🗓️: 0,
                title: "",
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

      let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
      let userModificationDate = now.addingTimeInterval(30)
      record.setValue("Buy milk", forKey: "title", at: userModificationDate)
      let modificationCallback = try {
        try syncEngine.modifyRecords(scope: .private, saving: [record])
      }()

      try await withDependencies {
        $0.date.now = now.addingTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.isCompleted = true }.execute(db)
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
                id🗓️: 0,
                isCompleted: 0,
                isCompleted🗓️: 0,
                remindersListID: 1,
                remindersListID🗓️: 0,
                title: "Buy milk",
                title🗓️: 30,
                🗓️: 30
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                id🗓️: 0,
                title: "",
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

      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      await modificationCallback.notify()

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
                id🗓️: 0,
                isCompleted: 1,
                isCompleted🗓️: 60,
                remindersListID: 1,
                remindersListID🗓️: 0,
                title: "Buy milk",
                title🗓️: 30,
                🗓️: 60
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                id🗓️: 0,
                title: "",
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
    }

    @Test func serverAndClientEditDifferentFields() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "")
          Reminder(id: 1, title: "", remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
      let userModificationDate = now.addingTimeInterval(30)
      record.setValue("Buy milk", forKey: "title", at: userModificationDate)
      let modificationCallback = try {
        try syncEngine.modifyRecords(scope: .private, saving: [record])
      }()

      try await withDependencies {
        $0.date.now = now.addingTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.isCompleted = true }.execute(db)
        }
      }
      await modificationCallback.notify()
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
                id🗓️: 0,
                isCompleted: 1,
                isCompleted🗓️: 60,
                remindersListID: 1,
                remindersListID🗓️: 0,
                title: "Buy milk",
                title🗓️: 30,
                🗓️: 60
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                id🗓️: 0,
                title: "",
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
    }

    @Test func serverRecordEditedAfterClientButProcessedBeforeClient() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "")
          Reminder(id: 1, title: "", remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
      let userModificationDate = now.addingTimeInterval(60)
      record.setValue("Buy milk", forKey: "title", at: userModificationDate)
      let modificationCallback = try {
        try syncEngine.modifyRecords(scope: .private, saving: [record])
      }()

      try await withDependencies {
        $0.date.now = now.addingTimeInterval(30)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.title = "Get milk" }.execute(db)
        }
      }
      await modificationCallback.notify()
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      try await userDatabase.userWrite { db in
        try #expect(
          Reminder.find(1).fetchOne(db)
            == Reminder(id: 1, title: "Get milk", remindersListID: 1)
        )
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
                id🗓️: 0,
                isCompleted: 0,
                isCompleted🗓️: 0,
                remindersListID: 1,
                remindersListID🗓️: 0,
                title: "Buy milk",
                title🗓️: 60,
                🗓️: 60
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                id🗓️: 0,
                title: "",
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
    }

    @Test func serverRecordEditedAndProcessedBeforeClient() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "")
          Reminder(id: 1, title: "", remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
      let userModificationDate = now.addingTimeInterval(30)
      record.setValue("Buy milk", forKey: "title", at: userModificationDate)
      let modificationCallback = try {
        try syncEngine.modifyRecords(scope: .private, saving: [record])
      }()

      try await withDependencies {
        $0.date.now = now.addingTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.title = "Get milk" }.execute(db)
        }
      }
      await modificationCallback.notify()
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
                id🗓️: 0,
                isCompleted: 0,
                isCompleted🗓️: 0,
                remindersListID: 1,
                remindersListID🗓️: 0,
                title: "Get milk",
                title🗓️: 60,
                🗓️: 60
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                id🗓️: 0,
                title: "",
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
    }

    @Test func serverRecordEditedBeforeClientButProcessedAfterClient() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "")
          Reminder(id: 1, title: "", remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let record = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
      let userModificationDate = now.addingTimeInterval(30)
      record.setValue("Buy milk", forKey: "title", at: userModificationDate)
      let modificationCallback = try {
        try syncEngine.modifyRecords(scope: .private, saving: [record])
      }()

      try await withDependencies {
        $0.date.now = now.addingTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.title = "Get milk" }.execute(db)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      await modificationCallback.notify()
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
                id🗓️: 0,
                isCompleted: 0,
                isCompleted🗓️: 0,
                remindersListID: 1,
                remindersListID🗓️: 0,
                title: "Get milk",
                title🗓️: 60,
                🗓️: 60
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                id🗓️: 0,
                title: "",
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
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func mergeWithNullableFields() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let reminderRecord = try syncEngine.private.database.record(
        for: Reminder.recordID(for: 1)
      )
      reminderRecord.setValue(
        now.addingTimeInterval(30),
        forKey: "dueDate",
        at: now.addingTimeInterval(1)
      )
      let modificationsFinished = try syncEngine.modifyRecords(
        scope: .private,
        saving: [reminderRecord]
      )

      try withDependencies {
        $0.date.now.addTimeInterval(2)
      } operation: {
        try userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.priority = 3 }.execute(db)
        }
      }

      await modificationsFinished.notify()
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
                dueDate: Date(1970-01-01T00:00:30.000Z),
                dueDate🗓️: 1,
                id: 1,
                id🗓️: 0,
                isCompleted: 0,
                isCompleted🗓️: 0,
                priority: 3,
                priority🗓️: 2,
                remindersListID: 1,
                remindersListID🗓️: 0,
                title: "",
                title🗓️: 0,
                🗓️: 2
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
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

      try await userDatabase.read { db in
        let reminder = try #require(try Reminder.find(1).fetchOne(db))
        #expect(
          reminder
            == Reminder(
              id: 1,
              dueDate: Date(timeIntervalSince1970: 30),
              priority: 3,
              remindersListID: 1
            )
        )
      }
    }
  }
}
