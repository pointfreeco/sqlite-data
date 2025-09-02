import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SQLiteData
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class ForeignKeyConstraintTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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
        record: remindersListRecord,
        action: .none
      )

      let remindersListModification = try syncEngine.modifyRecords(
        scope: .private,
        saving: [remindersListRecord]
      )
      try await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord]).notify()

      assertInlineSnapshot(of: container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                share: nil,
                id: 1,
                remindersListID: 1,
                title: "Get milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
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

        let remindersList = try #require(try RemindersList.find(1).fetchOne(db))
        #expect(remindersList == RemindersList(id: 1, title: "Personal"))

        let reminder = try #require(try Reminder.find(1).fetchOne(db))
        #expect(reminder == Reminder(id: 1, title: "Get milk", remindersListID: 1))
      }

      try await withDependencies {
        $0.datetime.now.addTimeInterval(1)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.title = "Buy milk" }.execute(db)
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      }

      assertInlineSnapshot(of: container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                share: nil,
                id: 1,
                isCompleted: 0,
                remindersListID: 1,
                title: "Buy milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
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
        let reminder = try #require(try Reminder.find(1).fetchOne(db))
        #expect(reminder == Reminder.init(id: 1, title: "Buy milk", remindersListID: 1))
      }
    }

    /*
     * Remote client creates records A <- B <- C
     * Records A and C are sync'd to local client.
     * Remote deletes record B and C.
     * C should be deleted from local client.
     */
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func remoteCreatesRecordABC_localReceivesAC_remoteDeletesBC() async throws {
      let modelARecord = CKRecord(recordType: ModelA.tableName, recordID: ModelA.recordID(for: 1))
      let modelBRecord = CKRecord(recordType: ModelB.tableName, recordID: ModelB.recordID(for: 1))
      modelBRecord.setValue(1, forKey: "modelAID", at: now)
      modelBRecord.parent = CKRecord.Reference(record: modelARecord, action: .none)
      let modelCRecord = CKRecord(recordType: ModelC.tableName, recordID: ModelC.recordID(for: 1))
      modelCRecord.setValue(1, forKey: "modelBID", at: now)
      modelCRecord.parent = CKRecord.Reference(record: modelBRecord, action: .none)

      try await syncEngine.modifyRecords(scope: .private, saving: [modelARecord]).notify()
      _ = try syncEngine.modifyRecords(scope: .private, saving: [modelBRecord])
      try await syncEngine.modifyRecords(scope: .private, saving: [modelCRecord]).notify()

      try await userDatabase.read { db in
        try #expect(
          UnsyncedRecordID.all.fetchAll(db) == [UnsyncedRecordID(recordID: ModelC.recordID(for: 1))]
        )
      }

      try await syncEngine.modifyRecords(
        scope: .private,
        deleting: [modelCRecord.recordID, modelBRecord.recordID]
      )
      .notify()

      try await userDatabase.read { db in
        try #expect(
          UnsyncedRecordID.all.fetchAll(db) == []
        )
      }

      assertInlineSnapshot(of: container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:modelAs/zone/__defaultOwner__),
                recordType: "modelAs",
                parent: nil,
                share: nil
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

    // * Receive child record with no parent record.
    // * Receive parent record.
    // => Both records are synchronized.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func receiveChildRecordBeforeParent_ReceiveChildAndParentRecord() async throws {
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
        record: remindersListRecord,
        action: .none
      )

      _ = try syncEngine.modifyRecords(scope: .private, saving: [remindersListRecord])
      try await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord]).notify()
      let freshReminderRecord = try syncEngine.private.database.record(
        for: Reminder.recordID(for: 1)
      )
      let freshRemindersListRecord = try syncEngine.private.database.record(
        for: RemindersList.recordID(for: 1)
      )
      try await syncEngine.modifyRecords(
        scope: .private,
        saving: [freshReminderRecord, freshRemindersListRecord]
      )
      .notify()

      assertInlineSnapshot(of: container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                share: nil,
                id: 1,
                remindersListID: 1,
                title: "Get milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
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
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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

      _ = try { try syncEngine.modifyRecords(scope: .private, saving: [remindersListRecord]) }()
      try await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord]).notify()

      assertInlineSnapshot(of: container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                share: nil,
                id: 1,
                remindersListID: 1,
                title: "Get milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
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
        tables: syncEngine.tables,
        privateTables: syncEngine.privateTables
      )

      await relaunchedSyncEngine
        .handleEvent(
          .fetchedRecordZoneChanges(modifications: [remindersListRecord], deletions: []),
          syncEngine: relaunchedSyncEngine.private
        )

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
        $0.datetime.now.addTimeInterval(1)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.title = "Buy milk" }.execute(db)
        }

        try await relaunchedSyncEngine.processPendingRecordZoneChanges(scope: .private)
      }

      assertInlineSnapshot(of: container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                share: nil,
                id: 1,
                isCompleted: 0,
                remindersListID: 1,
                title: "Buy milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
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
          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder.init(id: 1, title: "Buy milk", remindersListID: 1))
        }
    }

    // * Remote moves child to a parent the local client does not know about.
    // * Remote syncs child to local.
    // * Remote syncs parent to local.
    // => Parent and child records are synchronized.
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test
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
        record: personalListRecord,
        action: .none
      )
      
      try await syncEngine.modifyRecords(
        scope: .private,
        saving: [reminderRecord, personalListRecord]
      ).notify()
      
      assertInlineSnapshot(of: container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                share: nil,
                id: 1,
                remindersListID: 1,
                title: "Get milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
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
        $0.datetime.now.addTimeInterval(1)
      } operation: {
        let reminderRecord = try syncEngine.private.database.record(
          for: Reminder.recordID(for: 1)
        )
        reminderRecord.setValue(2, forKey: "remindersListID", at: now)
        reminderRecord.parent = CKRecord.Reference(record: businessListRecord, action: .none)
        
        let modifications = try syncEngine.modifyRecords(
          scope: .private,
          saving: [businessListRecord]
        )
        try await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord]).notify()
        return modifications
      }
      
      await modifications.notify()
      
      assertInlineSnapshot(of: container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(2:remindersLists/zone/__defaultOwner__)),
                share: nil,
                id: 1,
                remindersListID: 2,
                title: "Get milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                title: "Personal"
              ),
              [2]: CKRecord(
                recordID: CKRecord.ID(2:remindersLists/zone/__defaultOwner__),
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
      
      try await userDatabase.read { db in
        let reminder = try #require(try Reminder.find(1).fetchOne(db))
        #expect(reminder == Reminder(id: 1, title: "Get milk", remindersListID: 2))
        
        let reminderMetadata = try #require(
          try Reminder.metadata(for: 1)
            .fetchOne(db)
        )
        #expect(reminderMetadata.parentRecordName == "2:remindersLists")
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func changeParentRelationship_RemotelyThenLocally() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          RemindersList(id: 2, title: "Business")
          RemindersList(id: 3, title: "Secret")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let modifications = try withDependencies {
        $0.datetime.now.addTimeInterval(1)
      } operation: {
        let reminderRecord = try syncEngine.private.database
          .record(for: Reminder.recordID(for: 1))
        reminderRecord.setValue(2, forKey: "remindersListID", at: now)
        reminderRecord.parent = CKRecord.Reference(
          recordID: RemindersList.recordID(for: 2),
          action: .none
        )
        return try syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])
      }

      try await withDependencies {
        $0.datetime.now.addTimeInterval(2)
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

      await modifications.notify()

        try await userDatabase.read { db in
          let metadata = try #require(
            try Reminder.metadata(for: 1).fetchOne(db)
          )
          #expect(metadata.parentRecordName == RemindersList.recordName(for: 3))
          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder(id: 1, title: "Buy milk", remindersListID: 3))
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
          recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
          recordType: "reminders",
          parent: CKReference(recordID: CKRecord.ID(3:remindersLists/zone/__defaultOwner__)),
          share: nil,
          id: 1,
          isCompleted: 0,
          remindersListID: 3,
          title: "Buy milk"
        )
        """
      }

        try await userDatabase.read { db in
          let metadata = try #require(
            try Reminder.metadata(for: 1).fetchOne(db)
          )
          #expect(metadata.parentRecordName == RemindersList.recordName(for: 3))
          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder(id: 1, title: "Buy milk", remindersListID: 3))
        }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
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
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let modifications = try withDependencies {
        $0.datetime.now.addTimeInterval(1)
      } operation: {
        let reminderRecord = try syncEngine.private.database
          .record(for: Reminder.recordID(for: 1))
        reminderRecord.setValue(2, forKey: "remindersListID", at: now)
        reminderRecord.parent = CKRecord.Reference(
          recordID: RemindersList.recordID(for: 2),
          action: .none
        )
        return try syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])
      }

      try await withDependencies {
        $0.datetime.now.addTimeInterval(2)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).update { $0.remindersListID = 3 }.execute(db)
        }
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.read { db in
          let metadata = try #require(
            try Reminder.metadata(for: 1).fetchOne(db)
          )
          #expect(metadata.parentRecordName == RemindersList.recordName(for: 3))
          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder(id: 1, title: "Get milk", remindersListID: 3))
        }

      await modifications.notify()

      assertInlineSnapshot(
        of: syncEngine.private.database.storage[syncEngine.defaultZone.zoneID]?[
          Reminder.recordID(for: 1)
        ],
        as: .customDump
      ) {
        """
        CKRecord(
          recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
          recordType: "reminders",
          parent: CKReference(recordID: CKRecord.ID(3:remindersLists/zone/__defaultOwner__)),
          share: nil,
          id: 1,
          isCompleted: 0,
          remindersListID: 3,
          title: "Get milk"
        )
        """
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
          recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
          recordType: "reminders",
          parent: CKReference(recordID: CKRecord.ID(3:remindersLists/zone/__defaultOwner__)),
          share: nil,
          id: 1,
          isCompleted: 0,
          remindersListID: 3,
          title: "Get milk"
        )
        """
      }

        try await userDatabase.read { db in
          let metadata = try #require(
            try Reminder.metadata(for: 1).fetchOne(db)
          )
          #expect(metadata.parentRecordName == RemindersList.recordName(for: 3))
          let reminder = try #require(try Reminder.find(1).fetchOne(db))
          #expect(reminder == Reminder(id: 1, title: "Get milk", remindersListID: 3))
        }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func cascadingDeletes() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
          RemindersList(id: 2, title: "Work")
          Reminder(id: 2, title: "Call accountant", remindersListID: 2)
          RemindersList(id: 3, title: "Secret")
          Reminder(id: 3, title: "Schedule secret meeting", remindersListID: 3)
        }
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      try await userDatabase.userWrite { db in
        try RemindersList.where { $0.id <= 2 }.delete().execute(db)
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      assertInlineSnapshot(of: container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(3:reminders/zone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(3:remindersLists/zone/__defaultOwner__)),
                share: nil,
                id: 3,
                isCompleted: 0,
                remindersListID: 3,
                title: "Schedule secret meeting"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(3:remindersLists/zone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 3,
                title: "Secret"
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
