#if canImport(CloudKit)
  import CloudKit
  import DependenciesTestSupport
  import InlineSnapshotTesting
  import SQLiteDataTestSupport
  import OrderedCollections
  import SQLiteData
  import SnapshotTesting
  import SnapshotTestingCustomDump
  import Testing
  import os

  extension BaseCloudKitTests {
    @Suite
    struct SyncEngineLifecycleTests {
      @MainActor
      @Suite
      final class SyncEngineLifecycleTests_ImmediatelyStarted: BaseCloudKitTests,
        @unchecked
        Sendable
      {
        @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
        @Test func stopAndReStart() async throws {
          syncEngine.stop()

          try await userDatabase.userWrite { db in
            try db.seed {
              RemindersList(id: 1, title: "Personal")
              Reminder(id: 1, title: "Get milk", remindersListID: 1)
            }
          }

          try await Task.sleep(for: .seconds(1))

          assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
            """
            ┌──────────────────────────────────────────┐
            │ SyncMetadata(                            │
            │   id: SyncMetadata.ID(                   │
            │     recordPrimaryKey: "1",               │
            │     recordType: "remindersLists"         │
            │   ),                                     │
            │   zoneName: "zone",                      │
            │   ownerName: "__defaultOwner__",         │
            │   recordName: "1:remindersLists",        │
            │   parentRecordID: nil,                   │
            │   parentRecordName: nil,                 │
            │   lastKnownServerRecord: nil,            │
            │   _lastKnownServerRecordAllFields: nil,  │
            │   share: nil,                            │
            │   _isDeleted: false,                     │
            │   hasLastKnownServerRecord: false,       │
            │   isShared: false,                       │
            │   userModificationTime: 0                │
            │ )                                        │
            ├──────────────────────────────────────────┤
            │ SyncMetadata(                            │
            │   id: SyncMetadata.ID(                   │
            │     recordPrimaryKey: "1",               │
            │     recordType: "reminders"              │
            │   ),                                     │
            │   zoneName: "zone",                      │
            │   ownerName: "__defaultOwner__",         │
            │   recordName: "1:reminders",             │
            │   parentRecordID: SyncMetadata.ParentID( │
            │     parentRecordPrimaryKey: "1",         │
            │     parentRecordType: "remindersLists"   │
            │   ),                                     │
            │   parentRecordName: "1:remindersLists",  │
            │   lastKnownServerRecord: nil,            │
            │   _lastKnownServerRecordAllFields: nil,  │
            │   share: nil,                            │
            │   _isDeleted: false,                     │
            │   hasLastKnownServerRecord: false,       │
            │   isShared: false,                       │
            │   userModificationTime: 0                │
            │ )                                        │
            └──────────────────────────────────────────┘
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

          try await syncEngine.start()
          try await syncEngine.processPendingDatabaseChanges(scope: .private)
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

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
        }

        // * Create list
        // * Stop sync engine
        // * Delete list
        // * Start sync engine
        // => List is deleted from CloudKit
        @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
        @Test func writeStopDeleteStart() async throws {
          try await userDatabase.userWrite { db in
            try db.seed {
              RemindersList(id: 1, title: "Personal")
            }
          }
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

          syncEngine.stop()

          try await userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
          }

          try await Task.sleep(for: .seconds(1))

          try await syncEngine.start()
          try await syncEngine.processPendingDatabaseChanges(scope: .private)
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

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

        // * Stop sync engine
        // * Edit list
        // * Start sync engine
        // => List is updated on CloudKit
        @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
        @Test func addRemindersList_StopSyncEngine_EditTitle_StartSyncEngine() async throws {
          try await userDatabase.userWrite { db in
            try db.seed {
              RemindersList(id: 1, title: "Personal")
            }
          }
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

          syncEngine.stop()

          try await withDependencies {
            $0.currentTime.now += 1
          } operation: {
            try await userDatabase.userWrite { db in
              try RemindersList.find(1).update { $0.title += "!" }.execute(db)
            }
          }
          try await Task.sleep(for: .seconds(0.5))

          assertQuery(PendingRecordZoneChange.all, database: syncEngine.metadatabase) {
            """
            ┌─────────────────────────────────────────────────────────────────────────────────────────────┐
            │ PendingRecordZoneChange(                                                                    │
            │   pendingRecordZoneChange: .saveRecord(CKRecord.ID(1:remindersLists/zone/__defaultOwner__)) │
            │ )                                                                                           │
            └─────────────────────────────────────────────────────────────────────────────────────────────┘
            """
          }
          assertQuery(RemindersList.all, database: userDatabase.database) {
            """
            ┌──────────────────────┐
            │ RemindersList(       │
            │   id: 1,             │
            │   title: "Personal!" │
            │ )                    │
            └──────────────────────┘
            """
          }

          try await syncEngine.start()
          try await syncEngine.processPendingDatabaseChanges(scope: .private)
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

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
                    share: nil,
                    id: 1,
                    title: "Personal!"
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
          assertQuery(PendingRecordZoneChange.all, database: syncEngine.metadatabase) {
            """
            (No results)
            """
          }
        }

        @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
        @Test func getSharedRecord_StopSyncEngine_WriteToSharedRecord_StartSyncing() async throws {
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

          syncEngine.stop()

          try await withDependencies {
            $0.currentTime.now += 60
          } operation: {
            try await userDatabase.userWrite { db in
              try db.seed {
                Reminder(id: 1, title: "Get milk", remindersListID: 1)
              }
            }
          }

          try await Task.sleep(for: .seconds(1))
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
            │   lastKnownServerRecord: nil,                                                                       │
            │   _lastKnownServerRecordAllFields: nil,                                                             │
            │   share: nil,                                                                                       │
            │   _isDeleted: false,                                                                                │
            │   hasLastKnownServerRecord: false,                                                                  │
            │   isShared: false,                                                                                  │
            │   userModificationTime: 60                                                                          │
            │ )                                                                                                   │
            └─────────────────────────────────────────────────────────────────────────────────────────────────────┘
            """
          }

          try await Task.sleep(for: .seconds(0.5))
          try await syncEngine.start()
          try await syncEngine.processPendingDatabaseChanges(scope: .private)
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

        // Deleting a root shared record that we do not own while the sync engine is off will
        // probably sync (delete share on iCloud but does not delete any records) once the sync
        // engine is turned back on.
        @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
        @Test func externalSharedRecord_StopSyncEngine_DeleteSharedRecord_StartSyncEngine()
          async throws
        {
          let externalZoneID = CKRecordZone.ID(
            zoneName: "external.zone",
            ownerName: "external.owner"
          )
          let externalZone = CKRecordZone(zoneID: externalZoneID)
          try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()

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

          try await syncEngine.modifyRecords(
            scope: .shared,
            saving: [remindersListRecord, share]
          ).notify()

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

          syncEngine.stop()

          try await userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
          }
          try await Task.sleep(for: .seconds(1))

          try await syncEngine.start()
          try await syncEngine.processPendingDatabaseChanges(scope: .private)
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
        @Test func sharedRecord_StopSyncEngine_DeleteSharedRecord_StartSyncEngine() async throws {
          let remindersList = RemindersList(id: 1, title: "Personal")
          try await userDatabase.userWrite { db in
            try db.seed { remindersList }
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

          syncEngine.stop()

          try await userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
          }

          try await Task.sleep(for: .seconds(0.5))
          try await syncEngine.start()
          try await syncEngine.processPendingDatabaseChanges(scope: .private)
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

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

        // * Start with sync engine off
        // * Write a few rows
        // * Verify sync metadata is created.
        // * Verify cloud data is still empty
        // * Start sync engine
        // * Verify that data is sent to CloudKit database and cached locally.
        @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
        @Test(.startImmediately(false)) func writeAndThenStart() async throws {
          try await userDatabase.userWrite { db in
            try db.seed {
              RemindersList(id: 1, title: "Personal")
              Reminder(id: 1, title: "Get milk", remindersListID: 1)
            }
          }
          try await Task.sleep(for: .seconds(1))

          assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
            """
            ┌──────────────────────────────────────────┐
            │ SyncMetadata(                            │
            │   id: SyncMetadata.ID(                   │
            │     recordPrimaryKey: "1",               │
            │     recordType: "remindersLists"         │
            │   ),                                     │
            │   zoneName: "zone",                      │
            │   ownerName: "__defaultOwner__",         │
            │   recordName: "1:remindersLists",        │
            │   parentRecordID: nil,                   │
            │   parentRecordName: nil,                 │
            │   lastKnownServerRecord: nil,            │
            │   _lastKnownServerRecordAllFields: nil,  │
            │   share: nil,                            │
            │   _isDeleted: false,                     │
            │   hasLastKnownServerRecord: false,       │
            │   isShared: false,                       │
            │   userModificationTime: 0                │
            │ )                                        │
            ├──────────────────────────────────────────┤
            │ SyncMetadata(                            │
            │   id: SyncMetadata.ID(                   │
            │     recordPrimaryKey: "1",               │
            │     recordType: "reminders"              │
            │   ),                                     │
            │   zoneName: "zone",                      │
            │   ownerName: "__defaultOwner__",         │
            │   recordName: "1:reminders",             │
            │   parentRecordID: SyncMetadata.ParentID( │
            │     parentRecordPrimaryKey: "1",         │
            │     parentRecordType: "remindersLists"   │
            │   ),                                     │
            │   parentRecordName: "1:remindersLists",  │
            │   lastKnownServerRecord: nil,            │
            │   _lastKnownServerRecordAllFields: nil,  │
            │   share: nil,                            │
            │   _isDeleted: false,                     │
            │   hasLastKnownServerRecord: false,       │
            │   isShared: false,                       │
            │   userModificationTime: 0                │
            │ )                                        │
            └──────────────────────────────────────────┘
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

          try await syncEngine.start()
          await signIn()
          try await syncEngine.processPendingDatabaseChanges(scope: .private)
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

          assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
            """
            ┌─────────────────────────────────────────────────────────────────────────────────────────┐
            │ SyncMetadata(                                                                           │
            │   id: SyncMetadata.ID(                                                                  │
            │     recordPrimaryKey: "1",                                                              │
            │     recordType: "remindersLists"                                                        │
            │   ),                                                                                    │
            │   zoneName: "zone",                                                                     │
            │   ownerName: "__defaultOwner__",                                                        │
            │   recordName: "1:remindersLists",                                                       │
            │   parentRecordID: nil,                                                                  │
            │   parentRecordName: nil,                                                                │
            │   lastKnownServerRecord: CKRecord(                                                      │
            │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),                      │
            │     recordType: "remindersLists",                                                       │
            │     parent: nil,                                                                        │
            │     share: nil                                                                          │
            │   ),                                                                                    │
            │   _lastKnownServerRecordAllFields: CKRecord(                                            │
            │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),                      │
            │     recordType: "remindersLists",                                                       │
            │     parent: nil,                                                                        │
            │     share: nil,                                                                         │
            │     id: 1,                                                                              │
            │     title: "Personal"                                                                   │
            │   ),                                                                                    │
            │   share: nil,                                                                           │
            │   _isDeleted: false,                                                                    │
            │   hasLastKnownServerRecord: true,                                                       │
            │   isShared: false,                                                                      │
            │   userModificationTime: 0                                                               │
            │ )                                                                                       │
            ├─────────────────────────────────────────────────────────────────────────────────────────┤
            │ SyncMetadata(                                                                           │
            │   id: SyncMetadata.ID(                                                                  │
            │     recordPrimaryKey: "1",                                                              │
            │     recordType: "reminders"                                                             │
            │   ),                                                                                    │
            │   zoneName: "zone",                                                                     │
            │   ownerName: "__defaultOwner__",                                                        │
            │   recordName: "1:reminders",                                                            │
            │   parentRecordID: SyncMetadata.ParentID(                                                │
            │     parentRecordPrimaryKey: "1",                                                        │
            │     parentRecordType: "remindersLists"                                                  │
            │   ),                                                                                    │
            │   parentRecordName: "1:remindersLists",                                                 │
            │   lastKnownServerRecord: CKRecord(                                                      │
            │     recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),                           │
            │     recordType: "reminders",                                                            │
            │     parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)), │
            │     share: nil                                                                          │
            │   ),                                                                                    │
            │   _lastKnownServerRecordAllFields: CKRecord(                                            │
            │     recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),                           │
            │     recordType: "reminders",                                                            │
            │     parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)), │
            │     share: nil,                                                                         │
            │     id: 1,                                                                              │
            │     isCompleted: 0,                                                                     │
            │     remindersListID: 1,                                                                 │
            │     title: "Get milk"                                                                   │
            │   ),                                                                                    │
            │   share: nil,                                                                           │
            │   _isDeleted: false,                                                                    │
            │   hasLastKnownServerRecord: true,                                                       │
            │   isShared: false,                                                                      │
            │   userModificationTime: 0                                                               │
            │ )                                                                                       │
            └─────────────────────────────────────────────────────────────────────────────────────────┘
            """
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
        }
      }
    }
  }
#endif
