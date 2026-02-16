#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import Foundation
  import InlineSnapshotTesting
  import OrderedCollections
  import SQLiteData
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    @Suite
    final class FetchedDatabaseChangesTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteSyncEngineZone() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersList(id: 2, title: "Business")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
            Reminder(id: 2, title: "Call accountant", remindersListID: 2)
            RemindersListPrivate(remindersListID: 1)
            RemindersListPrivate(remindersListID: 2)
            UnsyncedModel(id: 1)
            UnsyncedModel(id: 2)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await syncEngine.modifyRecordZones(
          scope: .private,
          deleting: [syncEngine.defaultZone.zoneID]
        ).notify()
        try await syncEngine.processPendingDatabaseChanges(scope: .private)

        try await userDatabase.read { db in
          try #expect(Reminder.all.fetchAll(db) == [])
          try #expect(RemindersList.all.fetchAll(db) == [])
          try #expect(RemindersListPrivate.all.fetchAll(db) == [])
          try #expect(
            UnsyncedModel.all.fetchAll(db) == [UnsyncedModel(id: 1), UnsyncedModel(id: 2)]
          )
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteSyncEngineZone_EncryptedDataReset() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersList(id: 2, title: "Business")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
            Reminder(id: 2, title: "Call accountant", remindersListID: 2)
            RemindersListPrivate(remindersListID: 1)
            RemindersListPrivate(remindersListID: 2)
            UnsyncedModel(id: 1)
            UnsyncedModel(id: 2)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        await syncEngine
          .handleEvent(
            SyncEngine.Event.fetchedDatabaseChanges(
              modifications: [],
              deletions: [(syncEngine.defaultZone.zoneID, .encryptedDataReset)]
            ),
            syncEngine: syncEngine.private
          )
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.read { db in
          try #expect(Reminder.count().fetchOne(db) == 2)
          try #expect(RemindersList.count().fetchOne(db) == 2)
          try #expect(RemindersListPrivate.count().fetchOne(db) == 2)
          try #expect(UnsyncedModel.count().fetchOne(db) == 2)
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
                  recordID: CKRecord.ID(2:reminders/zone/__defaultOwner__),
                  recordType: "reminders",
                  parent: CKReference(recordID: CKRecord.ID(2:remindersLists/zone/__defaultOwner__)),
                  share: nil,
                  id: 2,
                  isCompleted: 0,
                  remindersListID: 2,
                  title: "Call accountant"
                ),
                [2]: CKRecord(
                  recordID: CKRecord.ID(1:remindersListPrivates/zone/__defaultOwner__),
                  recordType: "remindersListPrivates",
                  parent: nil,
                  share: nil,
                  position: 0,
                  remindersListID: 1
                ),
                [3]: CKRecord(
                  recordID: CKRecord.ID(2:remindersListPrivates/zone/__defaultOwner__),
                  recordType: "remindersListPrivates",
                  parent: nil,
                  share: nil,
                  position: 0,
                  remindersListID: 2
                ),
                [4]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: "Personal"
                ),
                [5]: CKRecord(
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
      }
    }
  }
#endif
