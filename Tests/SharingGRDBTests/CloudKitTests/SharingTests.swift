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
    @Dependency(\.date.now) var now

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareNonRootRecord() async throws {
      let reminder = Reminder(id: UUID(1), title: "Groceries", remindersListID: UUID(1))
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          reminder
        }
      }

      await syncEngine.processBatch()

      await #expect(throws: SyncEngine.RecordMustBeRoot.self) {
        _ = try await self.syncEngine.share(record: reminder, configure: { _ in })
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareUnrecognizedTable() async throws {
      await #expect(throws: SyncEngine.UnrecognizedTable.self) {
        _ = try await self.syncEngine.share(
          record: NonSyncedTable(id: UUID()),
          configure: { _ in }
        )
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func sharePrivateTable() async throws {
      await #expect(throws: SyncEngine.PrivateRootRecord.self) {
        _ = try await self.syncEngine.share(
          record: RemindersListPrivate(id: UUID(1), remindersListID: UUID(1)),
          configure: { _ in }
        )
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareRecordBeforeSync() async throws {
      await #expect(throws: SyncEngine.NoCKRecordFound.self) {
        _ = try await self.syncEngine.share(
          record: RemindersList(id: UUID(1)),
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

      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: UUID(1), zoneID: externalZoneID)
      )
      remindersListRecord.setValue(UUID(1).uuidString.lowercased(), forKey: "id", at: now)
      remindersListRecord.setValue(false, forKey: "isCompleted", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)

      await syncEngine.modifyRecords(scope: .shared, saving: [remindersListRecord])

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try db.seed {
            Reminder(id: UUID(1), title: "Get milk", remindersListID: UUID(1))
          }
        }
      }

      await syncEngine.processBatch()
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
                id: "00000000-0000-0000-0000-000000000001",
                isCompleted: 0,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                title: "Get milk"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
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
    @Test func shareeCreatesMultipleChildModels() async throws {
      let externalZoneID = CKRecordZone.ID(
        zoneName: "external.zone",
        ownerName: "external.owner"
      )

      let modelARecord = CKRecord(
        recordType: ModelA.tableName,
        recordID: ModelA.recordID(for: UUID(1), zoneID: externalZoneID)
      )
      modelARecord.setValue(UUID(1).uuidString.lowercased(), forKey: "id", at: now)
      modelARecord.setValue(0, forKey: "count", at: now)

      await syncEngine.modifyRecords(scope: .shared, saving: [modelARecord])

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try db.seed {
            ModelB(id: UUID(1), modelAID: UUID(1))
            ModelC(id: UUID(1), modelBID: UUID(1))
          }
        }
      }

      await syncEngine.processBatch()
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
                id: "00000000-0000-0000-0000-000000000001"
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),
                recordType: "modelBs",
                parent: CKReference(recordID: CKRecord.ID(1:modelAs/external.zone/external.owner)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                isOn: 0,
                modelAID: "00000000-0000-0000-0000-000000000001"
              ),
              [2]: CKRecord(
                recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),
                recordType: "modelCs",
                parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                modelBID: "00000000-0000-0000-0000-000000000001",
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
      let externalZoneID = CKRecordZone.ID(
        zoneName: "external.zone",
        ownerName: "external.owner"
      )

      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: UUID(1), zoneID: externalZoneID)
      )
      remindersListRecord.setValue(UUID(1).uuidString.lowercased(), forKey: "id", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)
      let reminderRecord = CKRecord(
        recordType: Reminder.tableName,
        recordID: Reminder.recordID(for: UUID(1), zoneID: externalZoneID)
      )
      reminderRecord.setValue(UUID(1).uuidString.lowercased(), forKey: "id", at: now)
      reminderRecord.setValue(false, forKey: "isCompleted", at: now)
      reminderRecord.setValue("Get milk", forKey: "title", at: now)
      reminderRecord.setValue(UUID(1).uuidString.lowercased(), forKey: "remindersListID", at: now)

      await syncEngine.modifyRecords(scope: .shared, saving: [remindersListRecord])

      try await withDependencies {
        $0.date.now.addTimeInterval(60)
      } operation: {
        try await userDatabase.userWrite { db in
          try Reminder.find(UUID(1)).delete().execute(db)
        }
      }

      await syncEngine.processBatch()
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
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal"
              )
            ]
          )
        )
        """
      }
    }

//    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
//    @Test func shareeCreatesMultipleRecords() async throws {
//      let otherSycnEngine = try await withDependencies {
//        $0.defaultOwnerName = "other-owner"
//      } operation: {
//        try await SyncEngine(
//          container: MockCloudContainer(
//            containerIdentifier: testContainerIdentifier,
//            privateCloudDatabase: MockCloudDatabase(databaseScope: .private),
//            sharedCloudDatabase: syncEngine.shared.database
//          ),
//          userDatabase: self.userDatabase,
//          metadatabaseURL: URL.metadatabase(containerIdentifier: testContainerIdentifier),
//          tables: [
//            ModelA.self,
//            ModelB.self,
//            ModelC.self,
//          ]
//        )
//      }
//
//      let rootModel = ModelA(id: UUID(1))
//      try await userDatabase.userWrite { db in
//        try db.seed {
//          rootModel
//          ModelB(id: UUID(1), modelAID: UUID(1))
//          ModelC(id: UUID(1), modelBID: UUID(1))
//        }
//      }
//
//      await syncEngine.processBatch()
//
//      let share = try await syncEngine.share(record: rootModel) { _ in }
//
//      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
//        """
//        MockCloudContainer(
//          privateCloudDatabase: MockCloudDatabase(
//            databaseScope: .private,
//            storage: [
//              [0]: CKRecord(
//                recordID: CKRecord.ID(75140E4A-A949-427F-96D9-88DAC532844A/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
//                recordType: "cloudkit.share",
//                parent: nil,
//                share: nil
//              ),
//              [1]: CKRecord(
//                recordID: CKRecord.ID(1:modelAs/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
//                recordType: "modelAs",
//                parent: nil,
//                share: CKReference(recordID: CKRecord.ID(75140E4A-A949-427F-96D9-88DAC532844A/co.pointfree.SQLiteData.defaultZone/__defaultOwner__))
//              )
//            ]
//          ),
//          sharedCloudDatabase: MockCloudDatabase(
//            databaseScope: .shared,
//            storage: []
//          )
//        )
//        """
//      }
//      assertInlineSnapshot(of: otherSycnEngine.container, as: .customDump) {
//        """
//        MockCloudContainer(
//          privateCloudDatabase: MockCloudDatabase(
//            databaseScope: .private,
//            storage: []
//          ),
//          sharedCloudDatabase: MockCloudDatabase(
//            databaseScope: .shared,
//            storage: []
//          )
//        )
//        """
//      }
//    }
  }
}

// TODO: Assert on Metadata.parentRecordName when create new reminders in a shared list

@Table private struct NonSyncedTable {
  let id: UUID
}
