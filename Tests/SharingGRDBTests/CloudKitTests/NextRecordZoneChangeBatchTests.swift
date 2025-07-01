import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class NextRecordZoneChangeBatchTests: BaseCloudKitTests, @unchecked Sendable {
    @Test func noMetadataForRecord() async throws {
      syncEngine.private.state.add(
        pendingRecordZoneChanges: [.saveRecord(Reminder.recordID(for: UUID(1)))]
      )

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
            storage: []
          )
        )
        """
      }
    }

    @Test func nonExistentTable() async throws {
      try await database.asyncWrite { db in
        try SyncMetadata.insert {
          SyncMetadata(
            recordType: UnrecognizedTable.tableName,
            recordName: SyncMetadata.RecordName(UnrecognizedTable.self, id: UUID(1)),
            userModificationDate: .distantPast
          )
        }
        .execute(db)
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
            storage: []
          )
        )
        """
      }
    }

    @Test func metadataRowWithNoCorrespondingRecordRow() async throws {
      try await database.asyncWrite { db in
        try SyncMetadata.insert {
          SyncMetadata(
            recordType: RemindersList.tableName,
            recordName: SyncMetadata.RecordName(RemindersList.self, id: UUID(1)),
            userModificationDate: .distantPast
          )
        }
        .execute(db)
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
            storage: []
          )
        )
        """
      }
    }

    @Test func saveRecord() async throws {
      try await database.asyncWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
        }
      }

      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
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
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
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

    @Test
    func saveRecordWithParent() async throws {
      try await database.asyncWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(1), title: "Get milk", remindersListID: UUID(1))
        }
      }

      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
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
                id: "00000000-0000-0000-0000-000000000001",
                isCompleted: 0,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                title: "Get milk",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
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

    @Test func savePrivateRecord() async throws {
      try await database.asyncWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          RemindersListPrivate(id: UUID(1), position: 42, remindersListID: UUID(1))
        }
      }

      await syncEngine.processBatch()
      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersListPrivates/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersListPrivates",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                position: 42,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                title: "Personal",
                sqlitedata_icloud_userModificationDate: Date(2009-02-13T23:31:30.000Z)
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
  let id: UUID
}
