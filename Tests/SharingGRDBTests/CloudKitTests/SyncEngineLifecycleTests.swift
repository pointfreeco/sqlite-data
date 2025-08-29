import CloudKit
import DependenciesTestSupport
import InlineSnapshotTesting
import OrderedCollections
import SharingGRDB
import SnapshotTesting
import SnapshotTestingCustomDump
import Testing
import os

extension BaseCloudKitTests {
  @Suite
  struct SyncEngineLifecycleTests {
    @MainActor
    @Suite
    final class SyncEngineLifecycleTests_ImmediatelyStarted: BaseCloudKitTests, @unchecked Sendable
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

        try await userDatabase.userRead { db in
          let remindersListMetadata = try #require(try RemindersList.metadata(for: 1).fetchOne(db))
          #expect(remindersListMetadata.lastKnownServerRecord == nil)

          let reminderMetadata = try #require(try Reminder.metadata(for: 1).fetchOne(db))
          #expect(reminderMetadata.lastKnownServerRecord == nil)
          #expect(reminderMetadata.parentRecordName == RemindersList.recordName(for: 1))
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
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container, as: .customDump) {
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
      }

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

        try await syncEngine.start()
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
          $0.datetime.now.addTimeInterval(1)
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).update { $0.title += "!" }.execute(db)
          }

          try await userDatabase.read { db in
            try #expect(PendingRecordZoneChange.all.fetchCount(db) == 1)
            try #expect(RemindersList.find(1).fetchOne(db)?.title == "Personal!")
          }

          try await syncEngine.start()
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)

          assertInlineSnapshot(of: container, as: .customDump) {
            """
            MockCloudContainer(
              privateCloudDatabase: MockCloudDatabase(
                databaseScope: .private,
                storage: [
                  [0]: CKRecord(
                    recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
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

          try await userDatabase.read { db in
            try #expect(PendingRecordZoneChange.all.fetchCount(db) == 0)
          }
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

        try await syncEngine.modifyRecordZones(scope: .shared, saving: [externalZone]).notify()
        try await syncEngine.modifyRecords(scope: .shared, saving: [remindersListRecord]).notify()

        syncEngine.stop()

        try await withDependencies {
          $0.datetime.now.addTimeInterval(60)
        } operation: {
          try await userDatabase.userWrite { db in
            try db.seed {
              Reminder(id: 1, title: "Get milk", remindersListID: 1)
            }
          }
        }

        try await syncEngine.start()
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
      @Test func externalSharedRecord_StopSyncEngine_DeleteSharedRecord_StartSyncEngine()
        async throws
      {
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

        syncEngine.stop()

        try await userDatabase.userWrite { db in
          try RemindersList.find(1).delete().execute(db)
        }

        try await syncEngine.start()
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
              storage: []
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

        syncEngine.stop()

        try await userDatabase.userWrite { db in
          try RemindersList.find(1).delete().execute(db)
        }

        try await syncEngine.start()
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
    }

    @MainActor
    final class SyncEngineLifecycleTests_ImmediatelyStopped: BaseCloudKitTests, @unchecked Sendable
    {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      init() async throws {
        try await super.init(startImmediately: false)
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func writeAndThenStart() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
          }
        }

        try await userDatabase.userRead { db in
          let remindersListMetadata = try #require(try RemindersList.metadata(for: 1).fetchOne(db))
          #expect(remindersListMetadata.lastKnownServerRecord == nil)

          let reminderMetadata = try #require(try Reminder.metadata(for: 1).fetchOne(db))
          #expect(reminderMetadata.lastKnownServerRecord == nil)
          #expect(reminderMetadata.parentRecordName == RemindersList.recordName(for: 1))
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

        assertInlineSnapshot(of: container, as: .customDump) {
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
      }
    }
  }
}
