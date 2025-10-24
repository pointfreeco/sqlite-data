#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import Foundation
  import InlineSnapshotTesting
  import SQLiteData
  import SnapshotTestingCustomDump
  import Testing
  import SQLiteDataTestSupport

  extension BaseCloudKitTests {
    @MainActor
    final class AccountLifecycleTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func signOutClearsUserDatabaseAndMetadatabase() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
            RemindersListPrivate(id: 1, remindersListID: 1)
            UnsyncedModel(id: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        await signOut()

        try await userDatabase.read { db in
          try #expect(RemindersList.count().fetchOne(db) == 0)
          try #expect(Reminder.count().fetchOne(db) == 0)
          try #expect(RemindersListPrivate.count().fetchOne(db) == 0)
          try #expect(UnsyncedModel.count().fetchOne(db) == 1)
        }

        try await syncEngine.metadatabase.read { db in
          try #expect(SyncMetadata.count().fetchOne(db) == 0)
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test(.accountStatus(.noAccount)) func signInUploadsLocalRecordsToCloudKit() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
            RemindersListPrivate(id: 1, remindersListID: 1)
            UnsyncedModel(id: 1)
          }
        }

        try await userDatabase.read { db in
          try #expect(RemindersList.count().fetchOne(db) == 1)
          try #expect(Reminder.count().fetchOne(db) == 1)
          try #expect(RemindersListPrivate.count().fetchOne(db) == 1)
          try #expect(UnsyncedModel.count().fetchOne(db) == 1)
        }
        try await syncEngine.metadatabase.read { db in
          try #expect(SyncMetadata.count().fetchOne(db) == 3)
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

        await signIn()

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
                  recordID: CKRecord.ID(1:remindersListPrivates/zone/__defaultOwner__),
                  recordType: "remindersListPrivates",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                  share: nil,
                  id: 1,
                  position: 0,
                  remindersListID: 1
                ),
                [2]: CKRecord(
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

    // * Create reminders list
    // * Soft log out
    // * Create reminder in list
    // * Sign in
    // * Reminder is sync'd to CloudKit
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func signInUploadsLocalRecordsToCloudKit_SkipExistingCloudKitRecords() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
        }
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)

      await softSignOut()

      try await userDatabase.userWrite { db in
        try db.seed {
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
        }
      }

      assertQuery(SyncMetadata.all, database: syncEngine.metadatabase) {
        """
        ┌────────────────────────────────────────────────────────────────────┐
        │ SyncMetadata(                                                      │
        │   id: SyncMetadata.ID(                                             │
        │     recordPrimaryKey: "1",                                         │
        │     recordType: "remindersLists"                                   │
        │   ),                                                               │
        │   zoneName: "zone",                                                │
        │   ownerName: "__defaultOwner__",                                   │
        │   recordName: "1:remindersLists",                                  │
        │   parentRecordID: nil,                                             │
        │   parentRecordName: nil,                                           │
        │   lastKnownServerRecord: CKRecord(                                 │
        │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__), │
        │     recordType: "remindersLists",                                  │
        │     parent: nil,                                                   │
        │     share: nil                                                     │
        │   ),                                                               │
        │   _lastKnownServerRecordAllFields: CKRecord(                       │
        │     recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__), │
        │     recordType: "remindersLists",                                  │
        │     parent: nil,                                                   │
        │     share: nil,                                                    │
        │     id: 1,                                                         │
        │     title: "Personal"                                              │
        │   ),                                                               │
        │   share: nil,                                                      │
        │   _isDeleted: false,                                               │
        │   hasLastKnownServerRecord: true,                                  │
        │   isShared: false,                                                 │
        │   userModificationTime: 0                                          │
        │ )                                                                  │
        ├────────────────────────────────────────────────────────────────────┤
        │ SyncMetadata(                                                      │
        │   id: SyncMetadata.ID(                                             │
        │     recordPrimaryKey: "1",                                         │
        │     recordType: "reminders"                                        │
        │   ),                                                               │
        │   zoneName: "zone",                                                │
        │   ownerName: "__defaultOwner__",                                   │
        │   recordName: "1:reminders",                                       │
        │   parentRecordID: SyncMetadata.ParentID(                           │
        │     parentRecordPrimaryKey: "1",                                   │
        │     parentRecordType: "remindersLists"                             │
        │   ),                                                               │
        │   parentRecordName: "1:remindersLists",                            │
        │   lastKnownServerRecord: nil,                                      │
        │   _lastKnownServerRecordAllFields: nil,                            │
        │   share: nil,                                                      │
        │   _isDeleted: false,                                               │
        │   hasLastKnownServerRecord: false,                                 │
        │   isShared: false,                                                 │
        │   userModificationTime: 0                                          │
        │ )                                                                  │
        └────────────────────────────────────────────────────────────────────┘
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

    // * Join shared reminders list
    // * Soft log out
    // * Create reminder in list
    // * Sign in
    // * Reminder is sync'd to CloudKit with proper metadata
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func createSharedRecordWhileSoftLoggedOut() async throws {
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
        for: remindersListRecord.recordID)

      try await syncEngine
        .acceptShare(
          metadata: ShareMetadata(
            containerIdentifier: container.containerIdentifier!,
            hierarchicalRootRecordID: freshRemindersListRecord.recordID,
            rootRecord: freshRemindersListRecord,
            share: freshShare
          )
        )

      await softSignOut()

      try await userDatabase.userWrite { db in
        try db.seed {
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
        }
      }

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
        │   lastKnownServerRecord: nil,                                                                       │
        │   _lastKnownServerRecordAllFields: nil,                                                             │
        │   share: nil,                                                                                       │
        │   _isDeleted: false,                                                                                │
        │   hasLastKnownServerRecord: false,                                                                  │
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

      await signIn()
      try await syncEngine.processPendingDatabaseChanges(scope: .private)
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

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test(
      .accountStatus(.noAccount),
      .prepareDatabase { userDatabase in
        try await userDatabase.write { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
            RemindersListPrivate(id: 1, remindersListID: 1)
            UnsyncedModel(id: 1)
          }
        }
      }
    )
    func doNotUploadExistingDataToCloudKitWhenSignedOut() {
      assertQuery(SyncMetadata.all, database: userDatabase.database) {
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
  }
#endif
