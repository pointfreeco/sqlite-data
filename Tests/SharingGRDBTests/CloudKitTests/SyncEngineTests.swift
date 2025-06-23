import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  final class SyncEngineTests: BaseCloudKitTests, @unchecked Sendable {
    //    #if os(macOS)
    //      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    //      @Test func foreignKeysDisabled() throws {
    //        let result = #expect(
    //          processExitsWith: .failure,
    //          observing: [\.standardErrorContent]
    //        ) {
    //          _ = try SyncEngine(
    //            privateSyncEngine: MockSyncEngine(scope: .private, state: MockSyncEngineState()),
    //            sharedSyncEngine: MockSyncEngine(scope: .shared, state: MockSyncEngineState()),
    //            database: databaseWithForeignKeys(),
    //            metadatabaseURL: URL.temporaryDirectory,
    //            tables: []
    //          )
    //        }
    //        #expect(
    //          String(decoding: try #require(result).standardOutputContent, as: UTF8.self)
    //          == "Foreign key support must be disabled to synchronize with CloudKit."
    //        )
    //      }
    //    #endif

    @Test func nextRecordZoneChangeBatch_NoMetadataForRecord() async throws {
      privateSyncEngine.state
        .add(pendingRecordZoneChanges: [.saveRecord(Reminder.recordID(for: UUID(1)))])
      #expect(privateSyncEngine.state.pendingRecordZoneChanges == [
        .saveRecord(Reminder.recordID(for: UUID(1)))
      ])

      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(
          options: CKSyncEngine.SendChangesOptions(
            scope: .recordIDs([Reminder.recordID(for: UUID(1))])
          )
        ).promoted,
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
        ).promoted,
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
        ).promoted,
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
      #expect(privateSyncEngine.state.pendingRecordZoneChanges == [
        .saveRecord(RemindersList.recordID(for: UUID(1)))
      ])

      let batch = await syncEngine._nextRecordZoneChangeBatch(
        SendChangesContext(
          options: CKSyncEngine.SendChangesOptions(
            scope: .recordIDs([RemindersList.recordID(for: UUID(1))])
          )
        ).promoted,
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
  }
}

private func databaseWithForeignKeys() throws -> any DatabaseWriter {
  try DatabaseQueue()
}

@Table struct UnrecognizedTable {
  let id: UUID
}
