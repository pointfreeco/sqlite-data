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
  final class SharingTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareNonRootRecord() async throws {
      let reminder = Reminder(id: 1, title: "Groceries", remindersListID: 1)
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          reminder
        }
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let error = await #expect(throws: (any Error).self) {
        _ = try await self.syncEngine.share(record: reminder, configure: { _ in })
      }
      assertInlineSnapshot(of: error?.localizedDescription, as: .customDump) {
        """
        "The record could not be shared."
        """
      }
      assertInlineSnapshot(of: error, as: .customDump) {
        """
        SyncEngine.SharingError(
          recordTableName: "reminders",
          recordPrimaryKey: "1",
          reason: .recordNotRoot(
            [
              [0]: ForeignKey(
                table: "remindersLists",
                from: "remindersListID",
                to: "id",
                onUpdate: .cascade,
                onDelete: .cascade,
                notnull: true
              )
            ]
          ),
          debugDescription: "Only root records are shareable, but parent record(s) detected via foreign key(s)."
        )
        """
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareUnrecognizedTable() async throws {
      let error = await #expect(throws: (any Error).self) {
        _ = try await self.syncEngine.share(
          record: UnsyncedModel(id: 42),
          configure: { _ in }
        )
      }
      assertInlineSnapshot(
        of: (error as? any LocalizedError)?.localizedDescription,
        as: .customDump
      ) {
        """
        "The record could not be shared."
        """
      }
      assertInlineSnapshot(of: error, as: .customDump) {
        #"""
        SyncEngine.SharingError(
          recordTableName: "unsyncedModels",
          recordPrimaryKey: "42",
          reason: .recordTableNotSynchronized,
          debugDescription: "Table is not shareable: table type not passed to \'tables\' parameter of \'SyncEngine.init\'."
        )
        """#
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func sharePrivateTable() async throws {
      let error = await #expect(throws: (any Error).self) {
        _ = try await self.syncEngine.share(
          record: RemindersListPrivate(id: 1, remindersListID: 1),
          configure: { _ in }
        )
      }
      assertInlineSnapshot(
        of: (error as? any LocalizedError)?.localizedDescription,
        as: .customDump
      ) {
        """
        "The record could not be shared."
        """
      }
      assertInlineSnapshot(of: error, as: .customDump) {
        """
        SyncEngine.SharingError(
          recordTableName: "remindersListPrivates",
          recordPrimaryKey: "1",
          reason: .recordNotRoot(
            [
              [0]: ForeignKey(
                table: "remindersLists",
                from: "remindersListID",
                to: "id",
                onUpdate: .noAction,
                onDelete: .cascade,
                notnull: true
              )
            ]
          ),
          debugDescription: "Only root records are shareable, but parent record(s) detected via foreign key(s)."
        )
        """
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareRecordBeforeSync() async throws {
      let error = await #expect(throws: (any Error).self) {
        _ = try await self.syncEngine.share(
          record: RemindersList(id: 1),
          configure: { _ in }
        )
      }
      assertInlineSnapshot(
        of: (error as? any LocalizedError)?.localizedDescription,
        as: .customDump
      ) {
        """
        "The record could not be shared."
        """
      }
      assertInlineSnapshot(of: error, as: .customDump) {
        """
        SyncEngine.SharingError(
          recordTableName: "remindersLists",
          recordPrimaryKey: "1",
          reason: .recordMetadataNotFound,
          debugDescription: "No sync metadata found for record. Has the record been saved to the database?"
        )
        """
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func createRecordInExternallySharedRecord() async throws {
      let externalZoneID = CKRecordZone.ID(
        zoneName: "external.zone",
        ownerName: "external.owner"
      )
      let externalZone = CKRecordZone(zoneID: externalZoneID)

      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: 1, zoneID: externalZoneID)
      )
      remindersListRecord.setValue(1, forKey: "id", at: now)
      remindersListRecord.setValue(false, forKey: "isCompleted", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)

      try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()
      try await syncEngine.modifyRecords(scope: .shared, saving: [remindersListRecord]).notify()

      try await withDependencies {
        $0.datetime.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try db.seed {
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
          }
        }
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .shared)
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: []
          ),
          sharedCloudDatabase: MockCloudDatabase(
            databaseScope: .shared,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/external.zone/external.owner),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner)),
                share: nil,
                id: 1,
                isCompleted: 0,
                remindersListID: 1,
                title: "Get milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                isCompleted: 0,
                title: "Personal"
              )
            ]
          )
        )
        """
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    func shareDelieveredBeforeRecord() async throws {
      let externalZone = CKRecordZone(
        zoneID: CKRecordZone.ID(
          zoneName: "external.zone",
          ownerName: "external.owner"
        )
      )
      try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()

      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: 1, zoneID: externalZone.zoneID)
      )
      remindersListRecord.setValue(1, forKey: "id", at: now)
      remindersListRecord.setValue(false, forKey: "isCompleted", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)

      let share = CKShare(
        rootRecord: remindersListRecord,
        shareID: CKRecord.ID(
          recordName: "Share-1",
          zoneID: externalZone.zoneID
        )
      )

      _ = try syncEngine.modifyRecords(scope: .private, saving: [share, remindersListRecord])

      let newShare = try syncEngine.private.database.record(for: share.recordID)
      let newRemindersListRecord = try syncEngine.private.database.record(
        for: remindersListRecord.recordID
      )
      try await syncEngine.modifyRecords(scope: .private, saving: [newShare]).notify()
      try await syncEngine.modifyRecords(scope: .private, saving: [newRemindersListRecord]).notify()

      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(Share-1/external.zone/external.owner),
                recordType: "cloudkit.share",
                parent: nil,
                share: nil
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                recordType: "remindersLists",
                parent: nil,
                share: CKReference(recordID: CKRecord.ID(Share-1/external.zone/external.owner)),
                id: 1,
                isCompleted: 0,
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

      let metadata = try await userDatabase.read { db in
        try SyncMetadata.order(by: \.recordName).fetchAll(db)
      }
      assertInlineSnapshot(of: metadata, as: .customDump) {
        """
        []
        """
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareeCreatesMultipleChildModels() async throws {
      let externalZoneID = CKRecordZone.ID(
        zoneName: "external.zone",
        ownerName: "external.owner"
      )
      let externalZone = CKRecordZone(zoneID: externalZoneID)

      let modelARecord = CKRecord(
        recordType: ModelA.tableName,
        recordID: ModelA.recordID(for: 1, zoneID: externalZoneID)
      )
      modelARecord.setValue(1, forKey: "id", at: now)
      modelARecord.setValue(0, forKey: "count", at: now)

      try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()
      try await syncEngine.modifyRecords(scope: .shared, saving: [modelARecord]).notify()

      try await withDependencies {
        $0.datetime.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try db.seed {
            ModelB(id: 1, modelAID: 1)
            ModelC(id: 1, modelBID: 1)
          }
        }
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .shared)
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: []
          ),
          sharedCloudDatabase: MockCloudDatabase(
            databaseScope: .shared,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:modelAs/external.zone/external.owner),
                recordType: "modelAs",
                parent: nil,
                share: nil,
                count: 0,
                id: 1
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),
                recordType: "modelBs",
                parent: CKReference(recordID: CKRecord.ID(1:modelAs/external.zone/external.owner)),
                share: nil,
                id: 1,
                isOn: 0,
                modelAID: 1
              ),
              [2]: CKRecord(
                recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),
                recordType: "modelCs",
                parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),
                share: nil,
                id: 1,
                modelBID: 1,
                title: ""
              )
            ]
          )
        )
        """
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteRecordInExternallySharedRecord() async throws {
      let externalZone = CKRecordZone(
        zoneID: CKRecordZone.ID(
          zoneName: "external.zone",
          ownerName: "external.owner"
        )
      )
      try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()

      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: 1, zoneID: externalZone.zoneID)
      )
      remindersListRecord.setValue(1, forKey: "id", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)
      let reminderRecord = CKRecord(
        recordType: Reminder.tableName,
        recordID: Reminder.recordID(for: 1, zoneID: externalZone.zoneID)
      )
      reminderRecord.setValue(1, forKey: "id", at: now)
      reminderRecord.setValue(false, forKey: "isCompleted", at: now)
      reminderRecord.setValue("Get milk", forKey: "title", at: now)
      reminderRecord.setValue(1, forKey: "remindersListID", at: now)
      reminderRecord.parent = CKRecord.Reference(record: remindersListRecord, action: .none)

      try await syncEngine.modifyRecords(
        scope: .shared,
        saving: [remindersListRecord, reminderRecord]
      ).notify()

      try await withDependencies {
        $0.datetime.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(1).delete().execute(db)
        }
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .shared)
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: []
          ),
          sharedCloudDatabase: MockCloudDatabase(
            databaseScope: .shared,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: 1,
                title: "Personal"
              )
            ]
          )
        )
        """
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func share() async throws {
      let remindersList = RemindersList(id: 1, title: "Personal")
      try await userDatabase.userWrite { db in
        try db.seed {
          remindersList
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      let sharedRecord = try await syncEngine.share(record: remindersList, configure: { _ in })

      try await userDatabase.read { db in
        let metadata = try #require(
          try SyncMetadata
            .where { $0.recordPrimaryKey.eq("1") }
            .fetchOne(db)
        )
        #expect(metadata.share?.recordID == sharedRecord.share.recordID)
      }

      assertInlineSnapshot(of: container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(share-1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "cloudkit.share",
                parent: nil,
                share: nil
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__))
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
    @Test func acceptShare() async throws {
      let externalZone = CKRecordZone(
        zoneID: CKRecordZone.ID(
          zoneName: "external.zone",
          ownerName: "external.owner"
        )
      )
      try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()

      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: 1, zoneID: externalZone.zoneID)
      )
      remindersListRecord.setValue(1, forKey: "id", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)

      try await syncEngine
        .acceptShare(
          metadata: ShareMetadata(
            containerIdentifier: container.containerIdentifier!,
            hierarchicalRootRecordID: remindersListRecord.recordID,
            rootRecord: remindersListRecord
          )
        )

      try await userDatabase.read { db in
        let remindersList = try #require(try RemindersList.find(1).fetchOne(db))
        let metadata = try #require(
          try SyncMetadata
          .where { $0.recordName.eq(remindersListRecord.recordID.recordName) }
          .fetchOne(db)
          )
        #expect(remindersList.title == "Personal")
        #expect(
          metadata.share?.recordID.recordName == "Share-\(remindersListRecord.recordID.recordName)"
        )
      }

      assertInlineSnapshot(of: container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: []
          ),
          sharedCloudDatabase: MockCloudDatabase(
            databaseScope: .shared,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(Share-1:remindersLists/external.zone/external.owner),
                recordType: "cloudkit.share",
                parent: nil,
                share: nil
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                recordType: "remindersLists",
                parent: nil,
                share: CKReference(recordID: CKRecord.ID(Share-1:remindersLists/external.zone/external.owner)),
                id: 1,
                title: "Personal"
              )
            ]
          )
        )
        """
      }
    }


    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func acceptShareCreateReminder() async throws {
      let externalZone = CKRecordZone(
        zoneID: CKRecordZone.ID(
          zoneName: "external.zone",
          ownerName: "external.owner"
        )
      )
      try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()

      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: 1, zoneID: externalZone.zoneID)
      )
      remindersListRecord.setValue(1, forKey: "id", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)

      try await syncEngine
        .acceptShare(
          metadata: ShareMetadata(
            containerIdentifier: container.containerIdentifier!,
            hierarchicalRootRecordID: remindersListRecord.recordID,
            rootRecord: remindersListRecord
          )
        )

      try await userDatabase.userWrite { db in
        try db.seed {
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
        }
      }

      try await syncEngine.processPendingRecordZoneChanges(scope: .shared)

      try await userDatabase.read { db in
        let metadata = try #require(
          try SyncMetadata
          .where { $0.recordName.eq("1:reminders") }
          .fetchOne(db)
          )
        #expect(metadata.parentRecordName == "1:remindersLists")
      }

      assertInlineSnapshot(of: container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: []
          ),
          sharedCloudDatabase: MockCloudDatabase(
            databaseScope: .shared,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(Share-1:remindersLists/external.zone/external.owner),
                recordType: "cloudkit.share",
                parent: nil,
                share: nil
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:reminders/external.zone/external.owner),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner)),
                share: nil,
                id: 1,
                isCompleted: 0,
                remindersListID: 1,
                title: "Get milk"
              ),
              [2]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                recordType: "remindersLists",
                parent: nil,
                share: CKReference(recordID: CKRecord.ID(Share-1:remindersLists/external.zone/external.owner)),
                id: 1,
                title: "Personal"
              )
            ]
          )
        )
        """
      }
    }
  }
}

// TODO: Assert on Metadata.parentRecordName when create new reminders in a shared list
