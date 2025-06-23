import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  final class NextRecordZoneChangeBatchTests: BaseCloudKitTests, @unchecked Sendable {
    @Test func nextRecordZoneChangeBatch_NoMetadataForRecord() async throws {
      privateSyncEngine.state
        .add(pendingRecordZoneChanges: [.saveRecord(Reminder.recordID(for: UUID(1)))])

      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(
          options: CKSyncEngine.SendChangesOptions(
            scope: .recordIDs([Reminder.recordID(for: UUID(1))])
          )
        ),
        syncEngine: privateSyncEngine
      )
      #expect(batch?.recordIDsToDelete == [])
      #expect(batch?.recordsToSave == [])

      #expect(privateSyncEngine.state.pendingRecordZoneChanges == [])
    }

    @Test func nextRecordZoneChangeBatch_NonExistentTable() async throws {
      try await database.write { db in
        try SyncMetadata.insert {
          SyncMetadata(
            recordType: UnrecognizedTable.tableName,
            recordName: SyncMetadata.RecordName(UnrecognizedTable.self, id: UUID(1))
          )
        }
        .execute(db)
      }
      privateSyncEngine.state
        .add(pendingRecordZoneChanges: [.saveRecord(UnrecognizedTable.recordID(for: UUID(1)))])
      #expect(!privateSyncEngine.state.pendingRecordZoneChanges.isEmpty)

      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(
          options: CKSyncEngine.SendChangesOptions(
            scope: .recordIDs([UnrecognizedTable.recordID(for: UUID(1))])
          )
        ),
        syncEngine: privateSyncEngine
      )
      #expect(batch?.recordIDsToDelete == [])
      #expect(batch?.recordsToSave == [])

      #expect(privateSyncEngine.state.pendingRecordZoneChanges.isEmpty)
    }

    @Test func nextRecordZoneChangeBatch_DeletedRow() async throws {
      try await database.write { db in
        try SyncMetadata.insert {
          SyncMetadata(
            recordType: RemindersList.tableName,
            recordName: SyncMetadata.RecordName(RemindersList.self, id: UUID(1))
          )
        }
        .execute(db)
      }
      privateSyncEngine.state
        .add(pendingRecordZoneChanges: [.saveRecord(RemindersList.recordID(for: UUID(1)))])
      #expect(!privateSyncEngine.state.pendingRecordZoneChanges.isEmpty)

      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(
          options: CKSyncEngine.SendChangesOptions(
            scope: .recordIDs([RemindersList.recordID(for: UUID(1))])
          )
        ),
        syncEngine: privateSyncEngine
      )
      #expect(batch?.recordIDsToDelete == [])
      #expect(batch?.recordsToSave == [])

      #expect(privateSyncEngine.state.pendingRecordZoneChanges.isEmpty)
    }

    @Test func nextRecordZoneChangeBatch_SaveRecord() async throws {
      try await database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
        }
      }
      #expect(
        privateSyncEngine.state.pendingRecordZoneChanges == [
          .saveRecord(RemindersList.recordID(for: UUID(1)))
        ]
      )

      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(
          options: CKSyncEngine.SendChangesOptions(
            scope: .recordIDs([RemindersList.recordID(for: UUID(1))])
          )
        ),
        syncEngine: privateSyncEngine
      )
      #expect(batch?.recordIDsToDelete == [])
      #expect(batch?.recordsToSave.count == 1)

      let savedRecord = try #require(batch?.recordsToSave.first)
      #expect(savedRecord.encryptedValues["title"] == "Personal")
      #expect(savedRecord.recordType == RemindersList.tableName)
      #expect(savedRecord.recordID == RemindersList.recordID(for: UUID(1)))

      #expect(privateSyncEngine.state.pendingRecordZoneChanges == [])
    }

    @Test func nextRecordZoneChangeBatch_SaveRecordWithParent() async throws {
      try await database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
        }
      }
      try await database.write { db in
        try db.seed {
          Reminder(id: UUID(1), title: "Get milk", remindersListID: UUID(1))
        }
      }
      #expect(
        privateSyncEngine.state.pendingRecordZoneChanges == [
          .saveRecord(RemindersList.recordID(for: UUID(1))),
          .saveRecord(Reminder.recordID(for: UUID(1))),
        ]
      )

      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(
          options: CKSyncEngine.SendChangesOptions(
            scope: .recordIDs([
              RemindersList.recordID(for: UUID(1)),
              Reminder.recordID(for: UUID(1)),
            ])
          )
        ),
        syncEngine: privateSyncEngine
      )
      #expect(batch?.recordIDsToDelete == [])
      #expect(batch?.recordsToSave.count == 2)

      let remindersListRecord = try #require(batch?.recordsToSave.first)
      let reminderRecord = try #require(batch?.recordsToSave.last)
      #expect(reminderRecord.encryptedValues["title"] == "Get milk")
      #expect(reminderRecord.recordType == Reminder.tableName)
      #expect(reminderRecord.recordID == Reminder.recordID(for: UUID(1)))
      #expect(reminderRecord.parent?.recordID == remindersListRecord.recordID)

      #expect(privateSyncEngine.state.pendingRecordZoneChanges == [])
    }
  }
}

@Table struct UnrecognizedTable {
  let id: UUID
}
