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
            userModificationDate: .distantPast
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
    @Test func metadataRowWithNoCorrespondingRecordRow() async throws {
      try await userDatabase.userWrite { db in
        try SyncMetadata.insert {
          SyncMetadata(
            recordPrimaryKey: "1",
            recordType: RemindersList.tableName,
            userModificationDate: .distantPast
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
    @Test func savePrivateRecord() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          RemindersListPrivate(id: 1, position: 42, remindersListID: 1)
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
                recordID: CKRecord.ID(1:remindersListPrivates/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersListPrivates",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: 1,
                position: 42,
                remindersListID: 1
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

@Table struct UnrecognizedTable {
  let id: UUID
}
