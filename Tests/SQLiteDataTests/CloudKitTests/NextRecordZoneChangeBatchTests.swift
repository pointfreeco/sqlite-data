#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import Foundation
  import InlineSnapshotTesting
  import SQLiteData
  import SQLiteDataTestSupport
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class NextRecordZoneChangeBatchTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func noMetadataForRecord() async throws {
        syncEngine.private.state.add(
          pendingRecordZoneChanges: [.saveRecord(Reminder.recordID(for: 1))]
        )

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
      @Test func nonExistentTable() async throws {
        try await userDatabase.userWrite { db in
          try SyncMetadata.insert {
            SyncMetadata(
              recordPrimaryKey: "1",
              recordType: UnrecognizedTable.tableName,
              zoneName: "zone-name",
              ownerName: "owner-name",
              userModificationTime: 0
            )
          }
          .execute(db)
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
              storage: []
            )
          )
          """
        }
      }

      // * CloudKit sends record for table we do not recognize.
      // * CloudKit deletes that record
      // => Local sync metadata should be deleted for that record.
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func cloudKitSendsNonExistentTable() async throws {
        let record = CKRecord(
          recordType: UnrecognizedTable.tableName,
          recordID: UnrecognizedTable.recordID(for: 1)
        )
        record.setValue(1, forKey: "id", at: now)
        try await syncEngine.modifyRecords(scope: .private, saving: [record]).notify()

        assertQuery(SyncMetadata.select(\.recordName), database: syncEngine.metadatabase) {
          """
          ┌────────────────────────┐
          │ "1:unrecognizedTables" │
          └────────────────────────┘
          """
        }

        try await syncEngine.modifyRecords(scope: .private, deleting: [record.recordID]).notify()

        assertQuery(SyncMetadata.select(\.recordName), database: syncEngine.metadatabase) {
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

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func metadataRowWithNoCorrespondingRecordRow() async throws {
        try await userDatabase.userWrite { db in
          try SyncMetadata.insert {
            SyncMetadata(
              recordPrimaryKey: "1",
              recordType: RemindersList.tableName,
              zoneName: syncEngine.defaultZone.zoneID.zoneName,
              ownerName: syncEngine.defaultZone.zoneID.ownerName,
              userModificationTime: 0
            )
          }
          .execute(db)
        }

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
      @Test func saveRecord() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }

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
      @Test func saveRecordWithParent() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, title: "Get milk", remindersListID: 1)
          }
        }

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

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func savePrivateRecord() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersListPrivate(remindersListID: 1, position: 42)
          }
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

  @Table struct UnrecognizedTable {
    let id: Int
  }
#endif
