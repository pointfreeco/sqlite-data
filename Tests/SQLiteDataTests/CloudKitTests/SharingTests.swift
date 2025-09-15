#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import SQLiteDataTestSupport
  import Foundation
  import GRDB
  import InlineSnapshotTesting
  import OrderedCollections
  import SQLiteData
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
                  isNotNull: true
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
                  isNotNull: true
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
            recordName: "share-\(remindersListRecord.recordID.recordName)",
            zoneID: externalZone.zoneID
          )
        )

        _ = try syncEngine.modifyRecords(scope: .shared, saving: [share, remindersListRecord])

        let newShare = try syncEngine.shared.database.record(for: share.recordID)
        let newRemindersListRecord = try syncEngine.shared.database.record(
          for: remindersListRecord.recordID
        )
        try await syncEngine.modifyRecords(scope: .shared, saving: [newShare]).notify()
        try await syncEngine.modifyRecords(scope: .shared, saving: [newRemindersListRecord])
          .notify()

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
                  recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner),
                  recordType: "cloudkit.share",
                  parent: nil,
                  share: nil
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                  recordType: "remindersLists",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner)),
                  id: 1,
                  isCompleted: 0,
                  title: "Personal"
                )
              ]
            )
          )
          """
        }

        assertQuery(SyncMetadata.order(by: \.recordName), database: syncEngine.metadatabase) {
          """
          ┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                                                       │
          │   recordPrimaryKey: "1",                                                                            │
          │   recordType: "remindersLists",                                                                     │
          │   recordName: "1:remindersLists",                                                                   │
          │   parentRecordPrimaryKey: nil,                                                                      │
          │   parentRecordType: nil,                                                                            │
          │   parentRecordName: nil,                                                                            │
          │   lastKnownServerRecord: CKRecord(                                                                  │
          │     recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),                           │
          │     recordType: "remindersLists",                                                                   │
          │     parent: nil,                                                                                    │
          │     share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner))  │
          │   ),                                                                                                │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                        │
          │     recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),                           │
          │     recordType: "remindersLists",                                                                   │
          │     parent: nil,                                                                                    │
          │     share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner)), │
          │     id: 1,                                                                                          │
          │     isCompleted: 0,                                                                                 │
          │     title: "Personal"                                                                               │
          │   ),                                                                                                │
          │   share: CKRecord(                                                                                  │
          │     recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner),                     │
          │     recordType: "cloudkit.share",                                                                   │
          │     parent: nil,                                                                                    │
          │     share: nil                                                                                      │
          │   ),                                                                                                │
          │   _isDeleted: false,                                                                                │
          │   hasLastKnownServerRecord: true,                                                                   │
          │   isShared: true,                                                                                   │
          │   userModificationDate: Date(1970-01-01T00:00:00.000Z)                                              │
          │ )                                                                                                   │
          └─────────────────────────────────────────────────────────────────────────────────────────────────────┘
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
        assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
          """
          ┌─────────────────────────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                                           │
          │   recordPrimaryKey: "1",                                                                │
          │   recordType: "modelAs",                                                                │
          │   recordName: "1:modelAs",                                                              │
          │   parentRecordPrimaryKey: nil,                                                          │
          │   parentRecordType: nil,                                                                │
          │   parentRecordName: nil,                                                                │
          │   lastKnownServerRecord: CKRecord(                                                      │
          │     recordID: CKRecord.ID(1:modelAs/external.zone/external.owner),                      │
          │     recordType: "modelAs",                                                              │
          │     parent: nil,                                                                        │
          │     share: nil                                                                          │
          │   ),                                                                                    │
          │   _lastKnownServerRecordAllFields: CKRecord(                                            │
          │     recordID: CKRecord.ID(1:modelAs/external.zone/external.owner),                      │
          │     recordType: "modelAs",                                                              │
          │     parent: nil,                                                                        │
          │     share: nil,                                                                         │
          │     count: 0,                                                                           │
          │     id: 1                                                                               │
          │   ),                                                                                    │
          │   share: nil,                                                                           │
          │   _isDeleted: false,                                                                    │
          │   hasLastKnownServerRecord: true,                                                       │
          │   isShared: false,                                                                      │
          │   userModificationDate: Date(1970-01-01T00:00:00.000Z)                                  │
          │ )                                                                                       │
          ├─────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                           │
          │   recordPrimaryKey: "1",                                                                │
          │   recordType: "modelBs",                                                                │
          │   recordName: "1:modelBs",                                                              │
          │   parentRecordPrimaryKey: "1",                                                          │
          │   parentRecordType: "modelAs",                                                          │
          │   parentRecordName: "1:modelAs",                                                        │
          │   lastKnownServerRecord: CKRecord(                                                      │
          │     recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),                      │
          │     recordType: "modelBs",                                                              │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelAs/external.zone/external.owner)), │
          │     share: nil                                                                          │
          │   ),                                                                                    │
          │   _lastKnownServerRecordAllFields: CKRecord(                                            │
          │     recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),                      │
          │     recordType: "modelBs",                                                              │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelAs/external.zone/external.owner)), │
          │     share: nil,                                                                         │
          │     id: 1,                                                                              │
          │     isOn: 0,                                                                            │
          │     modelAID: 1                                                                         │
          │   ),                                                                                    │
          │   share: nil,                                                                           │
          │   _isDeleted: false,                                                                    │
          │   hasLastKnownServerRecord: true,                                                       │
          │   isShared: false,                                                                      │
          │   userModificationDate: Date(1970-01-01T00:01:00.000Z)                                  │
          │ )                                                                                       │
          ├─────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                           │
          │   recordPrimaryKey: "1",                                                                │
          │   recordType: "modelCs",                                                                │
          │   recordName: "1:modelCs",                                                              │
          │   parentRecordPrimaryKey: "1",                                                          │
          │   parentRecordType: "modelBs",                                                          │
          │   parentRecordName: "1:modelBs",                                                        │
          │   lastKnownServerRecord: CKRecord(                                                      │
          │     recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),                      │
          │     recordType: "modelCs",                                                              │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)), │
          │     share: nil                                                                          │
          │   ),                                                                                    │
          │   _lastKnownServerRecordAllFields: CKRecord(                                            │
          │     recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),                      │
          │     recordType: "modelCs",                                                              │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)), │
          │     share: nil,                                                                         │
          │     id: 1,                                                                              │
          │     modelBID: 1,                                                                        │
          │     title: ""                                                                           │
          │   ),                                                                                    │
          │   share: nil,                                                                           │
          │   _isDeleted: false,                                                                    │
          │   hasLastKnownServerRecord: true,                                                       │
          │   isShared: false,                                                                      │
          │   userModificationDate: Date(1970-01-01T00:01:00.000Z)                                  │
          │ )                                                                                       │
          └─────────────────────────────────────────────────────────────────────────────────────────┘
          """
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

        let _ = try await syncEngine.share(record: remindersList, configure: { _ in })

        assertQuery(SyncMetadata.select(\.share), database: syncEngine.metadatabase) {
          """
          ┌────────────────────────────────────────────────────────────────────────┐
          │ CKRecord(                                                              │
          │   recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__), │
          │   recordType: "cloudkit.share",                                        │
          │   parent: nil,                                                         │
          │   share: nil                                                           │
          │ )                                                                      │
          └────────────────────────────────────────────────────────────────────────┘
          """
        }

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__),
                  recordType: "cloudkit.share",
                  parent: nil,
                  share: nil
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__))
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
      @Test func unshareNonSharedRecord() async throws {
        let remindersList = RemindersList(id: 1, title: "Personal")
        try await userDatabase.userWrite { db in
          try db.seed {
            remindersList
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withKnownIssue {
          try await syncEngine.unshare(record: remindersList)
        } matching: { issue in
          issue.description == """
            Issue recorded: No share found associated with record.
            """
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func shareUnshareShareAgain() async throws {
        let remindersList = RemindersList(id: 1, title: "Personal")
        try await userDatabase.userWrite { db in
          try db.seed {
            remindersList
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let _ = try await syncEngine.share(record: remindersList, configure: { _ in })

        try await syncEngine.unshare(record: remindersList)

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__))
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

        let _ = try await syncEngine.share(record: remindersList, configure: { _ in })

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__),
                  recordType: "cloudkit.share",
                  parent: nil,
                  share: nil
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__))
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
        let share = CKShare(
          rootRecord: remindersListRecord,
          shareID: CKRecord.ID(
            recordName: "share-\(remindersListRecord.recordID.recordName)",
            zoneID: remindersListRecord.recordID.zoneID
          )
        )
        _ = try syncEngine.modifyRecords(scope: .shared, saving: [share, remindersListRecord])
        let freshShare = try syncEngine.shared.database.record(for: share.recordID) as! CKShare
        let freshRemindersListRecord = try syncEngine.shared.database.record(
          for: remindersListRecord.recordID
        )

        try await syncEngine
          .acceptShare(
            metadata: ShareMetadata(
              containerIdentifier: container.containerIdentifier!,
              hierarchicalRootRecordID: freshRemindersListRecord.recordID,
              rootRecord: freshRemindersListRecord,
              share: freshShare
            )
          )

        assertQuery(SyncMetadata.select(\.share), database: syncEngine.metadatabase) {
          """
          ┌───────────────────────────────────────────────────────────────────────────────┐
          │ CKRecord(                                                                     │
          │   recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner), │
          │   recordType: "cloudkit.share",                                               │
          │   parent: nil,                                                                │
          │   share: nil                                                                  │
          │ )                                                                             │
          └───────────────────────────────────────────────────────────────────────────────┘
          """
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
                  recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner),
                  recordType: "cloudkit.share",
                  parent: nil,
                  share: nil
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner),
                  recordType: "remindersLists",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner)),
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
        let share = CKShare(
          rootRecord: remindersListRecord,
          shareID: CKRecord.ID(
            recordName: "share-\(remindersListRecord.recordID.recordName)",
            zoneID: remindersListRecord.recordID.zoneID
          )
        )

        try await syncEngine
          .acceptShare(
            metadata: ShareMetadata(
              containerIdentifier: container.containerIdentifier!,
              hierarchicalRootRecordID: remindersListRecord.recordID,
              rootRecord: remindersListRecord,
              share: share
            )
          )

        try await userDatabase.userWrite { db in
          try db.seed {
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .shared)

        assertQuery(
          SyncMetadata.select { ($0.recordName, $0.parentRecordName) },
          database: syncEngine.metadatabase
        ) {
          """
          ┌────────────────────┬────────────────────┐
          │ "1:remindersLists" │ nil                │
          │ "1:reminders"      │ "1:remindersLists" │
          └────────────────────┴────────────────────┘
          """
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
                  recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner),
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
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner)),
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
      @Test func deleteRootSharedRecord_CurrentUserOwnsRecord() async throws {
        let remindersList = RemindersList(id: 1, title: "Personal")
        try await userDatabase.userWrite { db in
          try db.seed {
            remindersList
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let _ = try await syncEngine.share(record: remindersList, configure: { _ in })

        try await userDatabase.userWrite { db in
          try RemindersList.find(1).delete().execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.userWrite { db in
          try #expect(RemindersList.all.fetchCount(db) == 0)
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
              storage: []
            )
          )
          """
        }
      }

      /// Deleting a root shared record that is not owned by current user should only delete
      /// the CKShare but not the actual records.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteRootSharedRecord_CurrentUserNotOwner() async throws {
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
        let share = CKShare(
          rootRecord: remindersListRecord,
          shareID: CKRecord.ID(
            recordName: "share-\(remindersListRecord.recordID.recordName)",
            zoneID: remindersListRecord.recordID.zoneID
          )
        )

        try await syncEngine
          .acceptShare(
            metadata: ShareMetadata(
              containerIdentifier: container.containerIdentifier!,
              hierarchicalRootRecordID: remindersListRecord.recordID,
              rootRecord: remindersListRecord,
              share: share
            )
          )

        try await userDatabase.userWrite { db in
          try db.seed {
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .shared)

        try await userDatabase.userWrite { db in
          try RemindersList.find(1).delete().execute(db)
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .shared)

        assertQuery(
          SyncMetadata.select { ($0.recordName, $0.share) },
          database: syncEngine.metadatabase
        ) {
          """
          """
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
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/external.zone/external.owner)),
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
      @Test func movesChildRecordFromPrivateParentToSharedParent() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            ModelA.Draft(id: 1, count: 42)
            ModelB.Draft(id: 1, isOn: true, modelAID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let externalZone = CKRecordZone(
          zoneID: CKRecordZone.ID(
            zoneName: "external.zone",
            ownerName: "external.owner"
          )
        )
        try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()

        let modelARecord = CKRecord(
          recordType: ModelA.tableName,
          recordID: ModelA.recordID(for: 2, zoneID: externalZone.zoneID)
        )
        modelARecord.setValue(2, forKey: "id", at: now)
        modelARecord.setValue(1729, forKey: "count", at: now)
        let share = CKShare(
          rootRecord: modelARecord,
          shareID: CKRecord.ID(
            recordName: "share-\(modelARecord.recordID.recordName)",
            zoneID: modelARecord.recordID.zoneID
          )
        )
        _ = try syncEngine.modifyRecords(scope: .shared, saving: [share, modelARecord])
        let freshShare = try syncEngine.shared.database.record(for: share.recordID) as! CKShare
        let freshModelARecord = try syncEngine.shared.database.record(for: modelARecord.recordID)

        try await syncEngine
          .acceptShare(
            metadata: ShareMetadata(
              containerIdentifier: container.containerIdentifier!,
              hierarchicalRootRecordID: freshModelARecord.recordID,
              rootRecord: freshModelARecord,
              share: freshShare
            )
          )

        let error = await #expect(throws: DatabaseError.self) {
          try await self.userDatabase.userWrite { db in
            try ModelB.find(1).update { $0.modelAID = 2 }.execute(db)
          }
        }
        #expect(error?.message == """
          The record '1:modelBs' was moved from zone 'zone/__defaultOwner__' to \
          'external.zone/external.owner'. This is currently not supported in SQLiteData. To work \
          around, delete the record and then create a new record with its new parent association.
          """)

        assertQuery(ModelB.all, database: userDatabase.database) {
          """
          ┌───────────────┐
          │ ModelB(       │
          │   id: 1,      │
          │   isOn: true, │
          │   modelAID: 1 │
          │ )             │
          └───────────────┘
          """
        }
        assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
          """
          ┌──────────────────────────────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                                                │
          │   recordPrimaryKey: "1",                                                                     │
          │   recordType: "modelAs",                                                                     │
          │   recordName: "1:modelAs",                                                                   │
          │   parentRecordPrimaryKey: nil,                                                               │
          │   parentRecordType: nil,                                                                     │
          │   parentRecordName: nil,                                                                     │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(1:modelAs/zone/__defaultOwner__),                                  │
          │     recordType: "modelAs",                                                                   │
          │     parent: nil,                                                                             │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(1:modelAs/zone/__defaultOwner__),                                  │
          │     recordType: "modelAs",                                                                   │
          │     parent: nil,                                                                             │
          │     share: nil,                                                                              │
          │     count: 42,                                                                               │
          │     id: 1                                                                                    │
          │   ),                                                                                         │
          │   share: nil,                                                                                │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: false,                                                                           │
          │   userModificationDate: Date(1970-01-01T00:00:00.000Z)                                       │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   recordPrimaryKey: "1",                                                                     │
          │   recordType: "modelBs",                                                                     │
          │   recordName: "1:modelBs",                                                                   │
          │   parentRecordPrimaryKey: "1",                                                               │
          │   parentRecordType: "modelAs",                                                               │
          │   parentRecordName: "1:modelAs",                                                             │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(1:modelBs/zone/__defaultOwner__),                                  │
          │     recordType: "modelBs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelAs/zone/__defaultOwner__)),             │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(1:modelBs/zone/__defaultOwner__),                                  │
          │     recordType: "modelBs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelAs/zone/__defaultOwner__)),             │
          │     share: nil,                                                                              │
          │     id: 1,                                                                                   │
          │     isOn: 1,                                                                                 │
          │     modelAID: 1                                                                              │
          │   ),                                                                                         │
          │   share: nil,                                                                                │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: false,                                                                           │
          │   userModificationDate: Date(1970-01-01T00:00:00.000Z)                                       │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   recordPrimaryKey: "2",                                                                     │
          │   recordType: "modelAs",                                                                     │
          │   recordName: "2:modelAs",                                                                   │
          │   parentRecordPrimaryKey: nil,                                                               │
          │   parentRecordType: nil,                                                                     │
          │   parentRecordName: nil,                                                                     │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(2:modelAs/external.zone/external.owner),                           │
          │     recordType: "modelAs",                                                                   │
          │     parent: nil,                                                                             │
          │     share: CKReference(recordID: CKRecord.ID(share-2:modelAs/external.zone/external.owner))  │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(2:modelAs/external.zone/external.owner),                           │
          │     recordType: "modelAs",                                                                   │
          │     parent: nil,                                                                             │
          │     share: CKReference(recordID: CKRecord.ID(share-2:modelAs/external.zone/external.owner)), │
          │     count: 1729,                                                                             │
          │     id: 2                                                                                    │
          │   ),                                                                                         │
          │   share: CKRecord(                                                                           │
          │     recordID: CKRecord.ID(share-2:modelAs/external.zone/external.owner),                     │
          │     recordType: "cloudkit.share",                                                            │
          │     parent: nil,                                                                             │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: true,                                                                            │
          │   userModificationDate: Date(1970-01-01T00:00:00.000Z)                                       │
          │ )                                                                                            │
          └──────────────────────────────────────────────────────────────────────────────────────────────┘
          """
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
                  share: nil,
                  count: 42,
                  id: 1
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:modelBs/zone/__defaultOwner__),
                  recordType: "modelBs",
                  parent: CKReference(recordID: CKRecord.ID(1:modelAs/zone/__defaultOwner__)),
                  share: nil,
                  id: 1,
                  isOn: 1,
                  modelAID: 1
                )
              ]
            ),
            sharedCloudDatabase: MockCloudDatabase(
              databaseScope: .shared,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(share-2:modelAs/external.zone/external.owner),
                  recordType: "cloudkit.share",
                  parent: nil,
                  share: nil
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(2:modelAs/external.zone/external.owner),
                  recordType: "modelAs",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-2:modelAs/external.zone/external.owner)),
                  count: 1729,
                  id: 2
                )
              ]
            )
          )
          """
        }
      }
    }
  }
#endif
