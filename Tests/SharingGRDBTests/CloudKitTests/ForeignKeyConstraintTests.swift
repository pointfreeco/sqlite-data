import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class ForeignKeyConstraintTests: BaseCloudKitTests, @unchecked Sendable {
    @Test func receiveChildBeforeParent() async throws {
      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: 1)
      )
      remindersListRecord.setValue(1, forKey: "id", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)

      let reminderRecord = CKRecord(
        recordType: Reminder.tableName,
        recordID: Reminder.recordID(for: 1)
      )
      reminderRecord.setValue(1, forKey: "id", at: now)
      reminderRecord.setValue("Get milk", forKey: "title", at: now)
      reminderRecord.setValue(1, forKey: "remindersListID", at: now)
      reminderRecord.parent = CKRecord.Reference(
        recordID: RemindersList.recordID(for: 1),
        action: .none
      )

      let remindersListModification = {
        syncEngine.modifyRecords(scope: .private, saving: [remindersListRecord])
      }()
      await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])

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
          ),
          sharedCloudDatabase: MockCloudDatabase(
            databaseScope: .shared,
            storage: []
          )
        )
        """
      }

      try await userDatabase.read { db in
        let remindersList = try RemindersList.find(1).fetchOne(db)
        #expect(remindersList == nil)
        let reminder = try Reminder.find(1).fetchOne(db)
        #expect(reminder == nil)
      }

      await remindersListModification()

      try {
        try userDatabase.read { db in
          let reminderMetadata = try #require(
            try SyncMetadata.find(1, table: Reminder.self).fetchOne(db)
          )
          #expect(reminderMetadata.recordName == Reminder.recordName(for: 1))
          #expect(reminderMetadata.parentRecordName == RemindersList.recordName(for: 1))

          let remindersListMetadata = try #require(
            try SyncMetadata.find(1, table: RemindersList.self).fetchOne(db)
          )
          #expect(remindersListMetadata.recordName == RemindersList.recordName(for: 1))
          #expect(remindersListMetadata.parentRecordName == nil)

          let remindersList = try #require(try RemindersList.find(1).fetchOne(db))
          #expect(remindersList == RemindersList(id: 1, title: "Personal"))

          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder(id: 1, title: "Get milk", remindersListID: 1))
        }
      }()

      try await withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.title = "Buy milk" }.execute(db)
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
                id: 1,
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

      try {
        try userDatabase.read { db in
          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder.init(id: 1, title: "Buy milk", remindersListID: 1))
        }
      }()
    }

    @Test(
      """
      1) Receive child record without parent.
      2) Receive child record with parent
      """
    ) func receiveChildRecordBeforeParent_ReceiveChildAndParentRecord() async throws {
      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: 1)
      )
      remindersListRecord.setValue(1, forKey: "id", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)

      let reminderRecord = CKRecord(
        recordType: Reminder.tableName,
        recordID: Reminder.recordID(for: 1)
      )
      reminderRecord.setValue(1, forKey: "id", at: now)
      reminderRecord.setValue("Get milk", forKey: "title", at: now)
      reminderRecord.setValue(1, forKey: "remindersListID", at: now)
      reminderRecord.parent = CKRecord.Reference(
        recordID: RemindersList.recordID(for: 1),
        action: .none
      )

      _ = {
        syncEngine.modifyRecords(scope: .private, saving: [remindersListRecord])
      }()
      await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])
      let freshReminderRecord = try syncEngine.private.database.record(for: Reminder.recordID(for: 1))
      let freshRemindersListRecord = try syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
      await syncEngine.modifyRecords(
        scope: .private,
        saving: [freshReminderRecord, freshRemindersListRecord]
      )

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
          try #expect(
            RemindersList.all.fetchAll(db) == [
              RemindersList(id: 1, title: "Personal")
            ]
          )
          try #expect(
            Reminder.all.fetchAll(db) == [
              Reminder(id: 1, title: "Get milk", remindersListID: 1)
            ]
          )
        }
      }()
    }

    @Test func receiveChild_Relaunch_ReceiveParent() async throws {
      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: 1)
      )
      remindersListRecord.setValue(1, forKey: "id", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)

      let reminderRecord = CKRecord(
        recordType: Reminder.tableName,
        recordID: Reminder.recordID(for: 1)
      )
      reminderRecord.setValue(1, forKey: "id", at: now)
      reminderRecord.setValue("Get milk", forKey: "title", at: now)
      reminderRecord.setValue(1, forKey: "remindersListID", at: now)
      reminderRecord.parent = CKRecord.Reference(
        recordID: RemindersList.recordID(for: 1),
        action: .none
      )

      _ = { syncEngine.modifyRecords(scope: .private, saving: [remindersListRecord]) }()
      await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])

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
          ),
          sharedCloudDatabase: MockCloudDatabase(
            databaseScope: .shared,
            storage: []
          )
        )
        """
      }

      try await userDatabase.read { db in
        let reminder = try Reminder.find(1).fetchOne(db)
        #expect(reminder == nil)
      }

      let relaunchedSyncEngine = try await SyncEngine(
        container: syncEngine.container,
        userDatabase: syncEngine.userDatabase,
        metadatabaseURL: URL(filePath: syncEngine.metadatabase.path),
        tables: syncEngine.tables,
        privateTables: syncEngine.privateTables
      )

      await relaunchedSyncEngine
        .handleEvent(
          .fetchedRecordZoneChanges(modifications: [remindersListRecord], deletions: []),
          syncEngine: relaunchedSyncEngine.private
        )

      try {
        try userDatabase.read { db in
          let reminderMetadata = try #require(
            try SyncMetadata.find(1, table: Reminder.self).fetchOne(db)
          )
          #expect(reminderMetadata.recordName == Reminder.recordName(for: 1))
          #expect(reminderMetadata.parentRecordName == RemindersList.recordName(for: 1))

          let remindersListMetadata = try #require(
            try SyncMetadata.find(1, table: RemindersList.self).fetchOne(db)
          )
          #expect(remindersListMetadata.recordName == RemindersList.recordName(for: 1))
          #expect(remindersListMetadata.parentRecordName == nil)

          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder(id: 1, title: "Get milk", remindersListID: 1))

          let remindersList = try #require(try RemindersList.find(1).fetchOne(db))
          #expect(remindersList == RemindersList(id: 1, title: "Personal"))
        }
      }()

      try await withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.title = "Buy milk" }.execute(db)
        }

        await relaunchedSyncEngine.processBatch()
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
                id: 1,
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

      try {
        try userDatabase.read { db in
          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder.init(id: 1, title: "Buy milk", remindersListID: 1))
        }
      }()
    }

    @Test(
      """
      Remote changes parent relationship to an unknown record which is synchronized later.
      """
    )
    func changeParentRelationshipToUnknownRecord() async throws {
      let personalListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: 1)
      )
      personalListRecord.setValue(1, forKey: "id", at: now)
      personalListRecord.setValue("Personal", forKey: "title", at: now)

      let businessListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: 2)
      )
      businessListRecord.setValue(2, forKey: "id", at: now)
      businessListRecord.setValue("Business", forKey: "title", at: now)

      let reminderRecord = CKRecord(
        recordType: Reminder.tableName,
        recordID: Reminder.recordID(for: 1)
      )
      reminderRecord.setValue(1, forKey: "id", at: now)
      reminderRecord.setValue("Get milk", forKey: "title", at: now)
      reminderRecord.setValue(1, forKey: "remindersListID", at: now)
      reminderRecord.parent = CKRecord.Reference(
        recordID: RemindersList.recordID(for: 1),
        action: .none
      )

      await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord, personalListRecord])

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
          ),
          sharedCloudDatabase: MockCloudDatabase(
            databaseScope: .shared,
            storage: []
          )
        )
        """
      }

      let modifications = try await withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        let reminderRecord = try syncEngine.private.database.record(
          for: Reminder.recordID(for: 1)
        )
        reminderRecord.setValue(2, forKey: "remindersListID", at: now)
        reminderRecord.parent = CKRecord.Reference(record: businessListRecord, action: .none)

        let modifications = {
          syncEngine.modifyRecords(scope: .private, saving: [businessListRecord])
        }()
        await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])
        return modifications
      }

      await modifications()

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
                remindersListID: 2,
                title: "Get milk"
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
                title: "Business"
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

      _ = try {
        try userDatabase.read { db in
          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder(id: 1, title: "Get milk", remindersListID: 2))

          let reminderMetadata = try #require(
            try SyncMetadata.find(1, table: Reminder.self)
              .fetchOne(db)
          )
          #expect(reminderMetadata.parentRecordName == "2:remindersLists")
        }
      }()
    }

    @Test func changeParentRelationship_RemotelyThenLocally() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          RemindersList(id: 2, title: "Business")
          RemindersList(id: 3, title: "Secret")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
        }
      }
      await syncEngine.processBatch()

      let modifications = try withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        let reminderRecord = try syncEngine.private.database
          .record(for: Reminder.recordID(for: 1))
        reminderRecord.setValue(2, forKey: "remindersListID", at: now)
        reminderRecord.parent = CKRecord.Reference(
          recordID: RemindersList.recordID(for: 2),
          action: .none
        )
        return syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])
      }

      try await withDependencies {
        $0.date.now.addTimeInterval(2)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1)
            .update {
              $0.title = "Buy milk"
              $0.remindersListID = 3
            }
            .execute(db)
        }
      }

      await modifications()

      try {
        try userDatabase.read { db in
          let metadata = try #require(
            try SyncMetadata.find(1, table: Reminder.self).fetchOne(db)
          )
          #expect(metadata.parentRecordName == RemindersList.recordName(for: 3))
          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder(id: 1, title: "Buy milk", remindersListID: 3))
        }
      }()

      await syncEngine.processBatch()

      assertInlineSnapshot(
        of: syncEngine.private.database.storage[Reminder.recordID(for: 1)],
        as: .customDump
      ) {
        """
        CKRecord(
          recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
          recordType: "reminders",
          parent: CKReference(recordID: CKRecord.ID(3:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
          share: nil,
          id: 1,
          isCompleted: 0,
          remindersListID: 3,
          title: "Buy milk"
        )
        """
      }

      try {
        try userDatabase.read { db in
          let metadata = try #require(
            try SyncMetadata.find(1, table: Reminder.self).fetchOne(db)
          )
          #expect(metadata.parentRecordName == RemindersList.recordName(for: 3))
          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder(id: 1, title: "Buy milk", remindersListID: 3))
        }
      }()
    }

    @Test
    func changeParentRelationship_RemoteFirstEdited_LocalSecondEdited_SendBatch_ReceiveCloudKit()
      async throws
    {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          RemindersList(id: 2, title: "Business")
          RemindersList(id: 3, title: "Secret")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
        }
      }
      await syncEngine.processBatch()

      let modifications = try withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        let reminderRecord = try syncEngine.private.database
          .record(for: Reminder.recordID(for: 1))
        reminderRecord.setValue(2, forKey: "remindersListID", at: now)
        reminderRecord.parent = CKRecord.Reference(
          recordID: RemindersList.recordID(for: 2),
          action: .none
        )
        return syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])
      }

      try await withDependencies {
        $0.date.now.addTimeInterval(2)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.remindersListID = 3 }.execute(db)
        }
      }

      await syncEngine.processBatch()

      try {
        try userDatabase.read { db in
          let metadata = try #require(
            try SyncMetadata.find(1, table: Reminder.self).fetchOne(db)
          )
          #expect(metadata.parentRecordName == RemindersList.recordName(for: 3))
          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder(id: 1, title: "Get milk", remindersListID: 3))
        }
      }()

      await modifications()

      assertInlineSnapshot(
        of: syncEngine.private.database.storage[Reminder.recordID(for: 1)],
        as: .customDump
      ) {
        """
        CKRecord(
          recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
          recordType: "reminders",
          parent: CKReference(recordID: CKRecord.ID(3:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
          share: nil,
          id: 1,
          isCompleted: 0,
          remindersListID: 3,
          title: "Get milk"
        )
        """
      }

      await syncEngine.processBatch()

      assertInlineSnapshot(
        of: syncEngine.private.database.storage[Reminder.recordID(for: 1)],
        as: .customDump
      ) {
        """
        CKRecord(
          recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
          recordType: "reminders",
          parent: CKReference(recordID: CKRecord.ID(3:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
          share: nil,
          id: 1,
          isCompleted: 0,
          remindersListID: 3,
          title: "Get milk"
        )
        """
      }

      try {
        try userDatabase.read { db in
          let metadata = try #require(
            try SyncMetadata.find(1, table: Reminder.self).fetchOne(db)
          )
          #expect(metadata.parentRecordName == RemindersList.recordName(for: 3))
          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder(id: 1, title: "Get milk", remindersListID: 3))
        }
      }()
    }
  }
}
