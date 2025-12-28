#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import SQLiteDataTestSupport
  import Foundation
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
      @Test func syncEngineStopped() async throws {
        let remindersList = RemindersList(id: 1, title: "Personal")
        try await userDatabase.userWrite { db in
          try db.seed { remindersList }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        syncEngine.stop()

        let error = await #expect(throws: (any Error).self) {
          _ = try await self.syncEngine.share(record: remindersList, configure: { _ in })
        }
        assertInlineSnapshot(of: error?.localizedDescription, as: .customDump) {
          """
          "The record could not be shared."
          """
        }
        assertInlineSnapshot(of: error, as: .customDump) {
          #"""
          SyncEngine.SharingError(
            recordTableName: nil,
            recordPrimaryKey: nil,
            reason: .syncEngineNotRunning,
            debugDescription: "Sync engine is not running. Make sure engine is running by invoking the \'start()\' method, or using the \'startImmediately\' argument when initializing the engine."
          )
          """#
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
            record: RemindersListPrivate(remindersListID: 1),
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
      @Test func privateTableNotShared() async throws {
        let remindersList = RemindersList(id: 1, title: "Personal")
        try await userDatabase.userWrite { db in
          try db.seed {
            remindersList
            RemindersListPrivate(remindersListID: 1, position: 42)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

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
                  recordID: CKRecord.ID(1:remindersListPrivates/zone/__defaultOwner__),
                  recordType: "remindersListPrivates",
                  parent: nil,
                  share: nil,
                  position: 42,
                  remindersListID: 1
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__)),
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
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func privateTablesStayInPrivateDatabase() async throws {
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

        try await userDatabase.userWrite { db in
          try RemindersListPrivate.insert {
            RemindersListPrivate(remindersListID: 1, position: 42)
          }
          .execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersListPrivates/zone/__defaultOwner__),
                  recordType: "remindersListPrivates",
                  parent: nil,
                  share: nil,
                  position: 42,
                  remindersListID: 1
                )
              ]
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
        let share = CKShare(
          rootRecord: remindersListRecord,
          shareID: CKRecord.ID(
            recordName: "share-\(remindersListRecord.recordID.recordName)",
            zoneID: remindersListRecord.recordID.zoneID
          )
        )

        try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()
        try await syncEngine.modifyRecords(
          scope: .shared,
          saving: [remindersListRecord, share]
        ).notify()

        try await withDependencies {
          $0.currentTime.now += 60
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
      @Test func shareDeliveredBeforeRecord() async throws {
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
          │   id: SyncMetadata.ID(                                                                              │
          │     recordPrimaryKey: "1",                                                                          │
          │     recordType: "remindersLists"                                                                    │
          │   ),                                                                                                │
          │   zoneName: "external.zone",                                                                        │
          │   ownerName: "external.owner",                                                                      │
          │   recordName: "1:remindersLists",                                                                   │
          │   parentRecordID: nil,                                                                              │
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
          │   userModificationTime: 0                                                                           │
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
        let share = CKShare(
          rootRecord: modelARecord,
          shareID: CKRecord.ID(
            recordName: "share-\(modelARecord.recordID.recordName)",
            zoneID: modelARecord.recordID.zoneID
          )
        )

        try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()
        try await syncEngine.modifyRecords(
          scope: .shared,
          saving: [modelARecord, share]
        ).notify()

        try await withDependencies {
          $0.currentTime.now += 60
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
          ┌──────────────────────────────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelAs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "1:modelAs",                                                                   │
          │   parentRecordID: nil,                                                                       │
          │   parentRecordName: nil,                                                                     │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(1:modelAs/external.zone/external.owner),                           │
          │     recordType: "modelAs",                                                                   │
          │     parent: nil,                                                                             │
          │     share: CKReference(recordID: CKRecord.ID(share-1:modelAs/external.zone/external.owner))  │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(1:modelAs/external.zone/external.owner),                           │
          │     recordType: "modelAs",                                                                   │
          │     parent: nil,                                                                             │
          │     share: CKReference(recordID: CKRecord.ID(share-1:modelAs/external.zone/external.owner)), │
          │     count: 0,                                                                                │
          │     id: 1                                                                                    │
          │   ),                                                                                         │
          │   share: CKRecord(                                                                           │
          │     recordID: CKRecord.ID(share-1:modelAs/external.zone/external.owner),                     │
          │     recordType: "cloudkit.share",                                                            │
          │     parent: nil,                                                                             │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: true,                                                                            │
          │   userModificationTime: 0                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelBs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "1:modelBs",                                                                   │
          │   parentRecordID: SyncMetadata.ParentID(                                                     │
          │     parentRecordPrimaryKey: "1",                                                             │
          │     parentRecordType: "modelAs"                                                              │
          │   ),                                                                                         │
          │   parentRecordName: "1:modelAs",                                                             │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),                           │
          │     recordType: "modelBs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelAs/external.zone/external.owner)),      │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),                           │
          │     recordType: "modelBs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelAs/external.zone/external.owner)),      │
          │     share: nil,                                                                              │
          │     id: 1,                                                                                   │
          │     isOn: 0,                                                                                 │
          │     modelAID: 1                                                                              │
          │   ),                                                                                         │
          │   share: nil,                                                                                │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: false,                                                                           │
          │   userModificationTime: 60                                                                   │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelCs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "1:modelCs",                                                                   │
          │   parentRecordID: SyncMetadata.ParentID(                                                     │
          │     parentRecordPrimaryKey: "1",                                                             │
          │     parentRecordType: "modelBs"                                                              │
          │   ),                                                                                         │
          │   parentRecordName: "1:modelBs",                                                             │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),                           │
          │     recordType: "modelCs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),      │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),                           │
          │     recordType: "modelCs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),      │
          │     share: nil,                                                                              │
          │     id: 1,                                                                                   │
          │     modelBID: 1,                                                                             │
          │     title: ""                                                                                │
          │   ),                                                                                         │
          │   share: nil,                                                                                │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: false,                                                                           │
          │   userModificationTime: 60                                                                   │
          │ )                                                                                            │
          └──────────────────────────────────────────────────────────────────────────────────────────────┘
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
                  recordID: CKRecord.ID(share-1:modelAs/external.zone/external.owner),
                  recordType: "cloudkit.share",
                  parent: nil,
                  share: nil
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:modelAs/external.zone/external.owner),
                  recordType: "modelAs",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:modelAs/external.zone/external.owner)),
                  count: 0,
                  id: 1
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),
                  recordType: "modelBs",
                  parent: CKReference(recordID: CKRecord.ID(1:modelAs/external.zone/external.owner)),
                  share: nil,
                  id: 1,
                  isOn: 0,
                  modelAID: 1
                ),
                [3]: CKRecord(
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
        let share = CKShare(
          rootRecord: remindersListRecord,
          shareID: CKRecord.ID(
            recordName: "share-\(remindersListRecord.recordID.recordName)",
            zoneID: remindersListRecord.recordID.zoneID
          )
        )

        try await syncEngine.modifyRecords(
          scope: .shared,
          saving: [remindersListRecord, reminderRecord, share]
        ).notify()

        try await withDependencies {
          $0.currentTime.now += 60
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
      @Test func share() async throws {
        let remindersList = RemindersList(id: 1, title: "Personal")
        try await userDatabase.userWrite { db in
          try db.seed {
            remindersList
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let _ = try await syncEngine.share(record: remindersList, configure: { _ in })

        assertQuery(
          SyncMetadata.select { ($0.share, $0.userModificationTime) },
          database: syncEngine.metadatabase
        ) {
          """
          ┌────────────────────────────────────────────────────────────────────────┬───┐
          │ CKRecord(                                                              │ 0 │
          │   recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__), │   │
          │   recordType: "cloudkit.share",                                        │   │
          │   parent: nil,                                                         │   │
          │   share: nil                                                           │   │
          │ )                                                                      │   │
          └────────────────────────────────────────────────────────────────────────┴───┘
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
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__)),
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
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func shareTwice() async throws {
        let remindersList = RemindersList(id: 1, title: "Personal")
        try await userDatabase.userWrite { db in
          try db.seed {
            remindersList
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let _ = try await syncEngine.share(
          record: remindersList,
          configure: {
            $0[CKShare.SystemFieldKey.title] = "Join my list!"
          })
        let _ = try await syncEngine.share(
          record: remindersList,
          configure: {
            $0[CKShare.SystemFieldKey.title] = "Please join my list!"
          })

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
                  share: nil,
                  cloudkit.title: "Please join my list!"
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__)),
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
      }

      // NB: Swift 6.2 cannot currently compile this:
      //     Pattern that the region based isolation checker does not understand how to check.
      //     Please file a bug.
      #if swift(<6.2)
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
            issue.description.hasSuffix(
              """
              Issue recorded: No share found associated with record.
              """
            )
          }
        }
      #endif

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
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__)),
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
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__)),
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

        assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
          """
          ┌─────────────────────────────────────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                                                       │
          │   id: SyncMetadata.ID(                                                                              │
          │     recordPrimaryKey: "1",                                                                          │
          │     recordType: "remindersLists"                                                                    │
          │   ),                                                                                                │
          │   zoneName: "external.zone",                                                                        │
          │   ownerName: "external.owner",                                                                      │
          │   recordName: "1:remindersLists",                                                                   │
          │   parentRecordID: nil,                                                                              │
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
          │   userModificationTime: 0                                                                           │
          │ )                                                                                                   │
          ├─────────────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                       │
          │   id: SyncMetadata.ID(                                                                              │
          │     recordPrimaryKey: "1",                                                                          │
          │     recordType: "reminders"                                                                         │
          │   ),                                                                                                │
          │   zoneName: "external.zone",                                                                        │
          │   ownerName: "external.owner",                                                                      │
          │   recordName: "1:reminders",                                                                        │
          │   parentRecordID: SyncMetadata.ParentID(                                                            │
          │     parentRecordPrimaryKey: "1",                                                                    │
          │     parentRecordType: "remindersLists"                                                              │
          │   ),                                                                                                │
          │   parentRecordName: "1:remindersLists",                                                             │
          │   lastKnownServerRecord: CKRecord(                                                                  │
          │     recordID: CKRecord.ID(1:reminders/external.zone/external.owner),                                │
          │     recordType: "reminders",                                                                        │
          │     parent: CKReference(recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner)),      │
          │     share: nil                                                                                      │
          │   ),                                                                                                │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                        │
          │     recordID: CKRecord.ID(1:reminders/external.zone/external.owner),                                │
          │     recordType: "reminders",                                                                        │
          │     parent: CKReference(recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner)),      │
          │     share: nil,                                                                                     │
          │     id: 1,                                                                                          │
          │     isCompleted: 0,                                                                                 │
          │     remindersListID: 1,                                                                             │
          │     title: "Get milk"                                                                               │
          │   ),                                                                                                │
          │   share: nil,                                                                                       │
          │   _isDeleted: false,                                                                                │
          │   hasLastKnownServerRecord: true,                                                                   │
          │   isShared: false,                                                                                  │
          │   userModificationTime: 0                                                                           │
          │ )                                                                                                   │
          └─────────────────────────────────────────────────────────────────────────────────────────────────────┘
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

      // Deleting a root shared record while the owner of that record deletes the associated CKShare
      // as well as any other associated records.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteRootSharedRecord_CurrentUserOwnsRecord() async throws {
        let remindersList = RemindersList(id: 1, title: "Personal")
        try await userDatabase.userWrite { db in
          try db.seed {
            remindersList
            Reminder(id: 1, remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

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
                  recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                  recordType: "reminders",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                  share: nil,
                  id: 1,
                  isCompleted: 0,
                  remindersListID: 1,
                  title: ""
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__)),
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
            Reminder(id: 2, title: "Take a walk", remindersListID: 1)
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
                  recordID: CKRecord.ID(2:reminders/external.zone/external.owner),
                  recordType: "reminders",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner)),
                  share: nil,
                  id: 2,
                  isCompleted: 0,
                  remindersListID: 1,
                  title: "Take a walk"
                ),
                [3]: CKRecord(
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

        try await userDatabase.userWrite { db in
          try RemindersList.find(1).delete().execute(db)
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .shared)

        assertQuery(Reminder.all, database: userDatabase.database) {
          """
          (No results)
          """
        }
        assertQuery(RemindersList.all, database: userDatabase.database) {
          """
          (No results)
          """
        }
        assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
          """
          (No results)
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
                  recordID: CKRecord.ID(2:reminders/external.zone/external.owner),
                  recordType: "reminders",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/external.zone/external.owner)),
                  share: nil,
                  id: 2,
                  isCompleted: 0,
                  remindersListID: 1,
                  title: "Take a walk"
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

      /// Deleting a root shared record that is not owned by current user should only delete
      /// the CKShare but not the actual records, including associated records.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteRootSharedRecord_CurrentUserNotOwner_DoNotCascade() async throws {
        let externalZone = CKRecordZone(
          zoneID: CKRecordZone.ID(
            zoneName: "external.zone",
            ownerName: "external.owner"
          )
        )
        try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()

        let modelARecord = CKRecord(
          recordType: ModelA.tableName,
          recordID: ModelA.recordID(for: 1, zoneID: externalZone.zoneID)
        )
        modelARecord.setValue(42, forKey: "count", at: now)

        let share = CKShare(
          rootRecord: modelARecord,
          shareID: CKRecord.ID(
            recordName: "share-\(modelARecord.recordID.recordName)",
            zoneID: modelARecord.recordID.zoneID
          )
        )

        try await syncEngine
          .acceptShare(
            metadata: ShareMetadata(
              containerIdentifier: container.containerIdentifier!,
              hierarchicalRootRecordID: modelARecord.recordID,
              rootRecord: modelARecord,
              share: share
            )
          )

        try await userDatabase.userWrite { db in
          try db.seed {
            ModelB(id: 1, isOn: true, modelAID: 1)
            ModelC(id: 1, title: "Hello world!", modelBID: 1)
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .shared)

        try await userDatabase.userWrite { db in
          try ModelA.find(1).delete().execute(db)
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .shared)

        assertQuery(Reminder.all, database: userDatabase.database) {
          """
          (No results)
          """
        }
        assertQuery(RemindersList.all, database: userDatabase.database) {
          """
          (No results)
          """
        }
        assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
          """
          (No results)
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
                  share: CKReference(recordID: CKRecord.ID(share-1:modelAs/external.zone/external.owner)),
                  count: 42
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),
                  recordType: "modelBs",
                  parent: CKReference(recordID: CKRecord.ID(1:modelAs/external.zone/external.owner)),
                  share: nil,
                  id: 1,
                  isOn: 1,
                  modelAID: 1
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),
                  recordType: "modelCs",
                  parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),
                  share: nil,
                  id: 1,
                  modelBID: 1,
                  title: "Hello world!"
                )
              ]
            )
          )
          """
        }
      }

      /// Syncing deletion of a root shared record that is not owned by current user should delete
      /// entire zone.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func syncDeletedRootSharedRecord_CurrentUserNotOwner() async throws {
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
            Reminder(id: 2, title: "Take a walk", remindersListID: 1)
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .shared)

        try await syncEngine.modifyRecordZones(scope: .shared, deleting: [externalZone.zoneID])
          .notify()

        assertQuery(Reminder.all, database: userDatabase.database) {
          """
          (No results)
          """
        }
        assertQuery(RemindersList.all, database: userDatabase.database) {
          """
          (No results)
          """
        }
        assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
          """
          (No results)
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
              storage: []
            )
          )
          """
        }
      }

      // NB: Come back to this when we have time to investigate.
      //      /// Deleting a root shared record that is not owned by current user should only delete
      //      /// the CKShare, not delete the actual CloudKit records, but delete all the local records.
      //      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      //      @Test func deleteRootSharedRecord_OnDeleteSetNull() async throws {
      //        let externalZone = CKRecordZone(
      //          zoneID: CKRecordZone.ID(
      //            zoneName: "external.zone",
      //            ownerName: "external.owner"
      //          )
      //        )
      //        try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()
      //
      //        let parentRecord = CKRecord(
      //          recordType: Parent.tableName,
      //          recordID: Parent.recordID(for: 1, zoneID: externalZone.zoneID)
      //        )
      //        parentRecord.setValue(1, forKey: "id", at: now)
      //        let share = CKShare(
      //          rootRecord: parentRecord,
      //          shareID: CKRecord.ID(
      //            recordName: "share-\(parentRecord.recordID.recordName)",
      //            zoneID: parentRecord.recordID.zoneID
      //          )
      //        )
      //
      //        try await syncEngine
      //          .acceptShare(
      //            metadata: ShareMetadata(
      //              containerIdentifier: container.containerIdentifier!,
      //              hierarchicalRootRecordID: parentRecord.recordID,
      //              rootRecord: parentRecord,
      //              share: share
      //            )
      //          )
      //
      //        try await userDatabase.userWrite { db in
      //          try db.seed {
      //            ChildWithOnDeleteSetNull(id: 1, parentID: 1)
      //          }
      //        }
      //
      //        try await syncEngine.processPendingRecordZoneChanges(scope: .shared)
      //
      //        try await userDatabase.userWrite { db in
      //          try Parent.find(1).delete().execute(db)
      //        }
      //
      //        try await syncEngine.processPendingRecordZoneChanges(scope: .shared)
      //
      //        assertQuery(Parent.all, database: userDatabase.database)
      //        assertQuery(ChildWithOnDeleteSetNull.all, database: userDatabase.database)
      //        assertQuery(SyncMetadata.all, database: syncEngine.metadatabase)
      //        assertInlineSnapshot(of: container, as: .customDump)
      //      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func movesChildRecordFromPrivateParentToSharedParent() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            ModelA.Draft(id: 1, count: 42)
            ModelB.Draft(id: 1, isOn: true, modelAID: 1)
            ModelC.Draft(id: 1, title: "Blob", modelBID: 1)
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

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await self.userDatabase.userWrite { db in
            try ModelB.find(1).update { $0.modelAID = 2 }.execute(db)
          }

          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
          try await syncEngine.processPendingRecordZoneChanges(scope: .shared)
        }

        assertQuery(ModelB.all, database: userDatabase.database) {
          """
          ┌───────────────┐
          │ ModelB(       │
          │   id: 1,      │
          │   isOn: true, │
          │   modelAID: 2 │
          │ )             │
          └───────────────┘
          """
        }
        assertQuery(ModelC.all, database: userDatabase.database) {
          """
          ┌──────────────────┐
          │ ModelC(          │
          │   id: 1,         │
          │   title: "Blob", │
          │   modelBID: 1    │
          │ )                │
          └──────────────────┘
          """
        }
        assertQuery(
          SyncMetadata.order { ($0.recordType, $0.recordName) },
          database: syncEngine.metadatabase
        ) {
          """
          ┌──────────────────────────────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelAs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "zone",                                                                          │
          │   ownerName: "__defaultOwner__",                                                             │
          │   recordName: "1:modelAs",                                                                   │
          │   parentRecordID: nil,                                                                       │
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
          │   userModificationTime: 0                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "2",                                                                   │
          │     recordType: "modelAs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "2:modelAs",                                                                   │
          │   parentRecordID: nil,                                                                       │
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
          │   userModificationTime: 0                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelBs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "1:modelBs",                                                                   │
          │   parentRecordID: SyncMetadata.ParentID(                                                     │
          │     parentRecordPrimaryKey: "2",                                                             │
          │     parentRecordType: "modelAs"                                                              │
          │   ),                                                                                         │
          │   parentRecordName: "2:modelAs",                                                             │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),                           │
          │     recordType: "modelBs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(2:modelAs/external.zone/external.owner)),      │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),                           │
          │     recordType: "modelBs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(2:modelAs/external.zone/external.owner)),      │
          │     share: nil,                                                                              │
          │     id: 1,                                                                                   │
          │     isOn: 1,                                                                                 │
          │     modelAID: 2                                                                              │
          │   ),                                                                                         │
          │   share: nil,                                                                                │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: false,                                                                           │
          │   userModificationTime: 1                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelCs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "1:modelCs",                                                                   │
          │   parentRecordID: SyncMetadata.ParentID(                                                     │
          │     parentRecordPrimaryKey: "1",                                                             │
          │     parentRecordType: "modelBs"                                                              │
          │   ),                                                                                         │
          │   parentRecordName: "1:modelBs",                                                             │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),                           │
          │     recordType: "modelCs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),      │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),                           │
          │     recordType: "modelCs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),      │
          │     share: nil,                                                                              │
          │     id: 1,                                                                                   │
          │     modelBID: 1,                                                                             │
          │     title: "Blob"                                                                            │
          │   ),                                                                                         │
          │   share: nil,                                                                                │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: false,                                                                           │
          │   userModificationTime: 0                                                                    │
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
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),
                  recordType: "modelBs",
                  parent: CKReference(recordID: CKRecord.ID(2:modelAs/external.zone/external.owner)),
                  share: nil,
                  id: 1,
                  isOn: 1,
                  modelAID: 2
                ),
                [3]: CKRecord(
                  recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),
                  recordType: "modelCs",
                  parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),
                  share: nil,
                  id: 1,
                  modelBID: 1,
                  title: "Blob"
                )
              ]
            )
          )
          """
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func movesChildRecordFromPrivateParentToSharedParent_ReceiveDeleteBeforeSave()
        async throws
      {
        try await userDatabase.userWrite { db in
          try db.seed {
            ModelA.Draft(id: 1, count: 42)
            ModelB.Draft(id: 1, isOn: true, modelAID: 1)
            ModelC.Draft(id: 1, title: "Blob", modelBID: 1)
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

        let movedModelBRecord = CKRecord(
          recordType: ModelB.tableName,
          recordID: ModelB.recordID(for: 1, zoneID: externalZone.zoneID)
        )
        movedModelBRecord.setValue(1, forKey: "id", at: now)
        movedModelBRecord.setValue(true, forKey: "isOn", at: now)
        movedModelBRecord.setValue(2, forKey: "modelAID", at: now)
        movedModelBRecord.parent = CKRecord.Reference(
          recordID: ModelA.recordID(for: 2, zoneID: externalZone.zoneID),
          action: .none
        )
        let movedModelCRecord = CKRecord(
          recordType: ModelC.tableName,
          recordID: ModelC.recordID(for: 1, zoneID: externalZone.zoneID)
        )
        movedModelCRecord.setValue(1, forKey: "id", at: now)
        movedModelCRecord.setValue("Blob", forKey: "title", at: now)
        movedModelCRecord.setValue(1, forKey: "modelBID", at: now)
        movedModelCRecord.parent = CKRecord.Reference(
          recordID: ModelB.recordID(for: 1, zoneID: externalZone.zoneID),
          action: .none
        )

        try await syncEngine.modifyRecords(
          scope: .private,
          deleting: [ModelB.recordID(for: 1), ModelC.recordID(for: 1)]
        ).notify()
        try await syncEngine.modifyRecords(
          scope: .shared,
          saving: [movedModelBRecord, movedModelCRecord]
        ).notify()

        assertQuery(ModelB.all, database: userDatabase.database) {
          """
          ┌───────────────┐
          │ ModelB(       │
          │   id: 1,      │
          │   isOn: true, │
          │   modelAID: 2 │
          │ )             │
          └───────────────┘
          """
        }
        assertQuery(ModelC.all, database: userDatabase.database) {
          """
          ┌──────────────────┐
          │ ModelC(          │
          │   id: 1,         │
          │   title: "Blob", │
          │   modelBID: 1    │
          │ )                │
          └──────────────────┘
          """
        }
        assertQuery(
          SyncMetadata.order { ($0.recordType, $0.recordName) },
          database: syncEngine.metadatabase
        ) {
          """
          ┌──────────────────────────────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelAs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "zone",                                                                          │
          │   ownerName: "__defaultOwner__",                                                             │
          │   recordName: "1:modelAs",                                                                   │
          │   parentRecordID: nil,                                                                       │
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
          │   userModificationTime: 0                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "2",                                                                   │
          │     recordType: "modelAs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "2:modelAs",                                                                   │
          │   parentRecordID: nil,                                                                       │
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
          │   userModificationTime: 0                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelBs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "1:modelBs",                                                                   │
          │   parentRecordID: SyncMetadata.ParentID(                                                     │
          │     parentRecordPrimaryKey: "2",                                                             │
          │     parentRecordType: "modelAs"                                                              │
          │   ),                                                                                         │
          │   parentRecordName: "2:modelAs",                                                             │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),                           │
          │     recordType: "modelBs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(2:modelAs/external.zone/external.owner)),      │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),                           │
          │     recordType: "modelBs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(2:modelAs/external.zone/external.owner)),      │
          │     share: nil,                                                                              │
          │     id: 1,                                                                                   │
          │     isOn: 1,                                                                                 │
          │     modelAID: 2                                                                              │
          │   ),                                                                                         │
          │   share: nil,                                                                                │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: false,                                                                           │
          │   userModificationTime: 0                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelCs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "1:modelCs",                                                                   │
          │   parentRecordID: SyncMetadata.ParentID(                                                     │
          │     parentRecordPrimaryKey: "1",                                                             │
          │     parentRecordType: "modelBs"                                                              │
          │   ),                                                                                         │
          │   parentRecordName: "1:modelBs",                                                             │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),                           │
          │     recordType: "modelCs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),      │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),                           │
          │     recordType: "modelCs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),      │
          │     share: nil,                                                                              │
          │     id: 1,                                                                                   │
          │     modelBID: 1,                                                                             │
          │     title: "Blob"                                                                            │
          │   ),                                                                                         │
          │   share: nil,                                                                                │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: false,                                                                           │
          │   userModificationTime: 0                                                                    │
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
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),
                  recordType: "modelBs",
                  parent: CKReference(recordID: CKRecord.ID(2:modelAs/external.zone/external.owner)),
                  share: nil,
                  id: 1,
                  isOn: 1,
                  modelAID: 2
                ),
                [3]: CKRecord(
                  recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),
                  recordType: "modelCs",
                  parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),
                  share: nil,
                  id: 1,
                  modelBID: 1,
                  title: "Blob"
                )
              ]
            )
          )
          """
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func movesChildRecordFromPrivateParentToSharedParent_ReceiveSaveBeforeDelete()
        async throws
      {
        try await userDatabase.userWrite { db in
          try db.seed {
            ModelA.Draft(id: 1, count: 42)
            ModelB.Draft(id: 1, isOn: true, modelAID: 1)
            ModelC.Draft(id: 1, title: "Blob", modelBID: 1)
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

        let movedModelBRecord = CKRecord(
          recordType: ModelB.tableName,
          recordID: ModelB.recordID(for: 1, zoneID: externalZone.zoneID)
        )
        movedModelBRecord.setValue(1, forKey: "id", at: now)
        movedModelBRecord.setValue(true, forKey: "isOn", at: now)
        movedModelBRecord.setValue(2, forKey: "modelAID", at: now)
        movedModelBRecord.parent = CKRecord.Reference(
          recordID: ModelA.recordID(for: 2, zoneID: externalZone.zoneID),
          action: .none
        )
        let movedModelCRecord = CKRecord(
          recordType: ModelC.tableName,
          recordID: ModelC.recordID(for: 1, zoneID: externalZone.zoneID)
        )
        movedModelCRecord.setValue(1, forKey: "id", at: now)
        movedModelCRecord.setValue("Blob", forKey: "title", at: now)
        movedModelCRecord.setValue(1, forKey: "modelBID", at: now)
        movedModelCRecord.parent = CKRecord.Reference(
          recordID: ModelB.recordID(for: 1, zoneID: externalZone.zoneID),
          action: .none
        )

        try await syncEngine.modifyRecords(
          scope: .shared,
          saving: [movedModelBRecord, movedModelCRecord]
        ).notify()
        try await syncEngine.modifyRecords(
          scope: .private,
          deleting: [ModelB.recordID(for: 1), ModelC.recordID(for: 1)]
        ).notify()

        assertQuery(ModelB.all, database: userDatabase.database) {
          """
          ┌───────────────┐
          │ ModelB(       │
          │   id: 1,      │
          │   isOn: true, │
          │   modelAID: 2 │
          │ )             │
          └───────────────┘
          """
        }
        assertQuery(ModelC.all, database: userDatabase.database) {
          """
          ┌──────────────────┐
          │ ModelC(          │
          │   id: 1,         │
          │   title: "Blob", │
          │   modelBID: 1    │
          │ )                │
          └──────────────────┘
          """
        }
        assertQuery(
          SyncMetadata.order { ($0.recordType, $0.recordName) },
          database: syncEngine.metadatabase
        ) {
          """
          ┌──────────────────────────────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelAs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "zone",                                                                          │
          │   ownerName: "__defaultOwner__",                                                             │
          │   recordName: "1:modelAs",                                                                   │
          │   parentRecordID: nil,                                                                       │
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
          │   userModificationTime: 0                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "2",                                                                   │
          │     recordType: "modelAs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "2:modelAs",                                                                   │
          │   parentRecordID: nil,                                                                       │
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
          │   userModificationTime: 0                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelBs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "1:modelBs",                                                                   │
          │   parentRecordID: SyncMetadata.ParentID(                                                     │
          │     parentRecordPrimaryKey: "2",                                                             │
          │     parentRecordType: "modelAs"                                                              │
          │   ),                                                                                         │
          │   parentRecordName: "2:modelAs",                                                             │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),                           │
          │     recordType: "modelBs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(2:modelAs/external.zone/external.owner)),      │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),                           │
          │     recordType: "modelBs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(2:modelAs/external.zone/external.owner)),      │
          │     share: nil,                                                                              │
          │     id: 1,                                                                                   │
          │     isOn: 1,                                                                                 │
          │     modelAID: 2                                                                              │
          │   ),                                                                                         │
          │   share: nil,                                                                                │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: false,                                                                           │
          │   userModificationTime: 0                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelCs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "1:modelCs",                                                                   │
          │   parentRecordID: SyncMetadata.ParentID(                                                     │
          │     parentRecordPrimaryKey: "1",                                                             │
          │     parentRecordType: "modelBs"                                                              │
          │   ),                                                                                         │
          │   parentRecordName: "1:modelBs",                                                             │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),                           │
          │     recordType: "modelCs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),      │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),                           │
          │     recordType: "modelCs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),      │
          │     share: nil,                                                                              │
          │     id: 1,                                                                                   │
          │     modelBID: 1,                                                                             │
          │     title: "Blob"                                                                            │
          │   ),                                                                                         │
          │   share: nil,                                                                                │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: false,                                                                           │
          │   userModificationTime: 0                                                                    │
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
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),
                  recordType: "modelBs",
                  parent: CKReference(recordID: CKRecord.ID(2:modelAs/external.zone/external.owner)),
                  share: nil,
                  id: 1,
                  isOn: 1,
                  modelAID: 2
                ),
                [3]: CKRecord(
                  recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),
                  recordType: "modelCs",
                  parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),
                  share: nil,
                  id: 1,
                  modelBID: 1,
                  title: "Blob"
                )
              ]
            )
          )
          """
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func movesChildRecordFromSharedParentToPrivateParent() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            ModelA.Draft(id: 1, count: 42)
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
        let modelBRecord = CKRecord(
          recordType: ModelB.tableName,
          recordID: ModelB.recordID(for: 1, zoneID: externalZone.zoneID)
        )
        modelBRecord.setValue(1, forKey: "id", at: now)
        modelBRecord.setValue(true, forKey: "isOne", at: now)
        modelBRecord.setValue(1, forKey: "modelAID", at: now)
        modelBRecord.parent = CKRecord.Reference(record: modelARecord, action: .none)

        _ =
          try syncEngine
          .modifyRecords(scope: .shared, saving: [share, modelARecord, modelBRecord])
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

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await self.userDatabase.userWrite { db in
            try ModelB.find(1).update { $0.modelAID = 1 }.execute(db)
          }

          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
          try await syncEngine.processPendingRecordZoneChanges(scope: .shared)
        }

        assertQuery(ModelB.all, database: userDatabase.database) {
          """
          ┌────────────────┐
          │ ModelB(        │
          │   id: 1,       │
          │   isOn: false, │
          │   modelAID: 1  │
          │ )              │
          └────────────────┘
          """
        }
        assertQuery(ModelC.all, database: userDatabase.database) {
          """
          (No results)
          """
        }
        assertQuery(
          SyncMetadata.order { ($0.recordType, $0.recordName) },
          database: syncEngine.metadatabase
        ) {
          """
          ┌──────────────────────────────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelAs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "zone",                                                                          │
          │   ownerName: "__defaultOwner__",                                                             │
          │   recordName: "1:modelAs",                                                                   │
          │   parentRecordID: nil,                                                                       │
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
          │   userModificationTime: 0                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "2",                                                                   │
          │     recordType: "modelAs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "2:modelAs",                                                                   │
          │   parentRecordID: nil,                                                                       │
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
          │   userModificationTime: 0                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelBs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "zone",                                                                          │
          │   ownerName: "__defaultOwner__",                                                             │
          │   recordName: "1:modelBs",                                                                   │
          │   parentRecordID: SyncMetadata.ParentID(                                                     │
          │     parentRecordPrimaryKey: "1",                                                             │
          │     parentRecordType: "modelAs"                                                              │
          │   ),                                                                                         │
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
          │     isOn: 0,                                                                                 │
          │     modelAID: 1                                                                              │
          │   ),                                                                                         │
          │   share: nil,                                                                                │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: false,                                                                           │
          │   userModificationTime: 1                                                                    │
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
                  isOn: 0,
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

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test
      func movesChildRecordFromPrivateParentToSharedParentWhileSyncEngineStopped() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            ModelA.Draft(id: 1, count: 42)
            ModelB.Draft(id: 1, isOn: true, modelAID: 1)
            ModelC.Draft(id: 1, title: "Blob", modelBID: 1)
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

        syncEngine.stop()

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await self.userDatabase.userWrite { db in
            try ModelB.find(1).update { $0.modelAID = 2 }.execute(db)
          }
        }

        try await syncEngine.start()
        try await syncEngine.processPendingDatabaseChanges(scope: .private)
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        try await syncEngine.processPendingRecordZoneChanges(scope: .shared)

        assertQuery(ModelB.all, database: userDatabase.database) {
          """
          ┌───────────────┐
          │ ModelB(       │
          │   id: 1,      │
          │   isOn: true, │
          │   modelAID: 2 │
          │ )             │
          └───────────────┘
          """
        }
        assertQuery(ModelC.all, database: userDatabase.database) {
          """
          ┌──────────────────┐
          │ ModelC(          │
          │   id: 1,         │
          │   title: "Blob", │
          │   modelBID: 1    │
          │ )                │
          └──────────────────┘
          """
        }
        assertQuery(
          SyncMetadata.order { ($0.recordType, $0.recordName) },
          database: syncEngine.metadatabase
        ) {
          """
          ┌──────────────────────────────────────────────────────────────────────────────────────────────┐
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelAs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "zone",                                                                          │
          │   ownerName: "__defaultOwner__",                                                             │
          │   recordName: "1:modelAs",                                                                   │
          │   parentRecordID: nil,                                                                       │
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
          │   userModificationTime: 0                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "2",                                                                   │
          │     recordType: "modelAs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "2:modelAs",                                                                   │
          │   parentRecordID: nil,                                                                       │
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
          │   userModificationTime: 0                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelBs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "1:modelBs",                                                                   │
          │   parentRecordID: SyncMetadata.ParentID(                                                     │
          │     parentRecordPrimaryKey: "2",                                                             │
          │     parentRecordType: "modelAs"                                                              │
          │   ),                                                                                         │
          │   parentRecordName: "2:modelAs",                                                             │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),                           │
          │     recordType: "modelBs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(2:modelAs/external.zone/external.owner)),      │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),                           │
          │     recordType: "modelBs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(2:modelAs/external.zone/external.owner)),      │
          │     share: nil,                                                                              │
          │     id: 1,                                                                                   │
          │     isOn: 1,                                                                                 │
          │     modelAID: 2                                                                              │
          │   ),                                                                                         │
          │   share: nil,                                                                                │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: false,                                                                           │
          │   userModificationTime: 1                                                                    │
          │ )                                                                                            │
          ├──────────────────────────────────────────────────────────────────────────────────────────────┤
          │ SyncMetadata(                                                                                │
          │   id: SyncMetadata.ID(                                                                       │
          │     recordPrimaryKey: "1",                                                                   │
          │     recordType: "modelCs"                                                                    │
          │   ),                                                                                         │
          │   zoneName: "external.zone",                                                                 │
          │   ownerName: "external.owner",                                                               │
          │   recordName: "1:modelCs",                                                                   │
          │   parentRecordID: SyncMetadata.ParentID(                                                     │
          │     parentRecordPrimaryKey: "1",                                                             │
          │     parentRecordType: "modelBs"                                                              │
          │   ),                                                                                         │
          │   parentRecordName: "1:modelBs",                                                             │
          │   lastKnownServerRecord: CKRecord(                                                           │
          │     recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),                           │
          │     recordType: "modelCs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),      │
          │     share: nil                                                                               │
          │   ),                                                                                         │
          │   _lastKnownServerRecordAllFields: CKRecord(                                                 │
          │     recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),                           │
          │     recordType: "modelCs",                                                                   │
          │     parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),      │
          │     share: nil,                                                                              │
          │     id: 1,                                                                                   │
          │     modelBID: 1,                                                                             │
          │     title: "Blob"                                                                            │
          │   ),                                                                                         │
          │   share: nil,                                                                                │
          │   _isDeleted: false,                                                                         │
          │   hasLastKnownServerRecord: true,                                                            │
          │   isShared: false,                                                                           │
          │   userModificationTime: 0                                                                    │
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
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:modelBs/external.zone/external.owner),
                  recordType: "modelBs",
                  parent: CKReference(recordID: CKRecord.ID(2:modelAs/external.zone/external.owner)),
                  share: nil,
                  id: 1,
                  isOn: 1,
                  modelAID: 2
                ),
                [3]: CKRecord(
                  recordID: CKRecord.ID(1:modelCs/external.zone/external.owner),
                  recordType: "modelCs",
                  parent: CKReference(recordID: CKRecord.ID(1:modelBs/external.zone/external.owner)),
                  share: nil,
                  id: 1,
                  modelBID: 1,
                  title: "Blob"
                )
              ]
            )
          )
          """
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteShare() async throws {
        let remindersList = RemindersList(id: 1, title: "Personal")
        try await userDatabase.userWrite { db in
          try db.seed {
            remindersList
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let sharedRecord = try await syncEngine.share(record: remindersList, configure: { _ in })

        try await syncEngine
          .modifyRecords(scope: .private, deleting: [sharedRecord.share.recordID])
          .notify()

        assertQuery(SyncMetadata.select(\.share), database: syncEngine.metadatabase) {
          """
          ┌─────┐
          │ nil │
          └─────┘
          """
        }
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
                  share: CKReference(recordID: CKRecord.ID(share-1:remindersLists/zone/__defaultOwner__)),
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
      }
    }
  }
#endif
