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

      await #expect(throws: SyncEngine.RecordMustBeRoot.self) {
        _ = try await self.syncEngine.share(record: reminder, configure: { _ in })
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareUnrecognizedTable() async throws {
      await #expect(throws: SyncEngine.UnrecognizedTable.self) {
        _ = try await self.syncEngine.share(
          record: UnsyncedModel(id: 42),
          configure: { _ in }
        )
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func sharePrivateTable() async throws {
      await #expect(throws: SyncEngine.PrivateRootRecord.self) {
        _ = try await self.syncEngine.share(
          record: RemindersListPrivate(id: 1, remindersListID: 1),
          configure: { _ in }
        )
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareRecordBeforeSync() async throws {
      await #expect(throws: SyncEngine.NoCKRecordFound.self) {
        _ = try await self.syncEngine.share(
          record: RemindersList(id: 1),
          configure: { _ in }
        )
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
        $0.date.now.addTimeInterval(60)
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
    @Test func shareDelieveredBeforeRecord() async throws {
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
          recordName: "Share-\(1)",
          zoneID: externalZone.zoneID
        )
      )

      try await syncEngine.modifyRecords(scope: .shared, saving: [share]).notify()
      try await syncEngine.modifyRecords(scope: .shared, saving: [remindersListRecord]).notify()

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
          )
        )
        """
      }

      let metadata = try await userDatabase.read { db in
        try SyncMetadata.order(by: \.recordName).fetchAll(db)
      }
      assertInlineSnapshot(of: metadata, as: .customDump) {
        """
        [
          [0]: SyncMetadata(
            recordPrimaryKey: "1",
            recordType: "remindersLists",
            recordName: "1:remindersLists",
            parentRecordPrimaryKey: nil,
            parentRecordType: nil,
            parentRecordName: nil,
            lastKnownServerRecord: CKRecord(
              recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
              recordType: "remindersLists",
              parent: nil,
              share: CKReference(recordID: CKRecord.ID(Share-1/external.zone/external.owner))
            ),
            _lastKnownServerRecordAllFields: CKRecord(
              recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
              recordType: "remindersLists",
              parent: nil,
              share: CKReference(recordID: CKRecord.ID(Share-1/external.zone/external.owner)),
              id: 1,
              isCompleted: 0,
              title: "Personal"
            ),
            share: nil,
            isShared: false,
            userModificationDate: Date(1970-01-01T00:00:00.000Z)
          )
        ]
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
        $0.date.now.addTimeInterval(60)
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

      try await syncEngine.modifyRecords(scope: .shared, saving: [remindersListRecord, reminderRecord]).notify()

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
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
  }
}

// TODO: Assert on Metadata.parentRecordName when create new reminders in a shared list
