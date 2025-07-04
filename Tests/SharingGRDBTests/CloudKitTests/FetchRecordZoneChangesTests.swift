import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import OrderedCollections
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  @Suite(.printTimestamps) final class FetchRecordZoneChangeTests: BaseCloudKitTests, @unchecked Sendable {
    @Dependency(\.date.now) var now

    @Test func saveExtraFieldsToSyncMetadata() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          Reminder(id: UUID(1), title: "Get milk", remindersListID: UUID(1))
        }
      }
      await syncEngine.processBatch()

      let reminderRecord = try syncEngine.private.database
        .record(for: Reminder.recordID(for: UUID(1)))
      reminderRecord.setValue("Hello world! 🌎🌎🌎", forKey: "newField", at: now)

      await syncEngine.modifyRecords(scope: .private, saving: [reminderRecord])

      do {
        let lastKnownServerRecords = try await syncEngine.metadatabase.read { db in
          try SyncMetadata
            .order(by: \.recordName)
            .select(\._lastKnownServerRecordAllFields)
            .fetchAll(db)
        }
        assertInlineSnapshot(of: lastKnownServerRecords, as: .customDump) {
          """
          [
            [0]: CKRecord(
              recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
              recordType: "reminders",
              parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
              share: nil,
              id: "00000000-0000-0000-0000-000000000001",
              id🗓️: 0,
              isCompleted: 0,
              isCompleted🗓️: 0,
              newField: "Hello world! 🌎🌎🌎",
              newField🗓️: 0,
              remindersListID: "00000000-0000-0000-0000-000000000001",
              remindersListID🗓️: 0,
              title: "Get milk",
              title🗓️: 0,
              🗓️: 0
            ),
            [1]: CKRecord(
              recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
              recordType: "remindersLists",
              parent: nil,
              share: nil,
              id: "00000000-0000-0000-0000-000000000001",
              id🗓️: 0,
              title: "Personal",
              title🗓️: 0,
              🗓️: 0
            )
          ]
          """
        }
      }

      try await withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
      try await userDatabase.userWrite { db in
        try Reminder.find(UUID(1)).update { $0.isCompleted.toggle() }.execute(db)
      }

      await syncEngine.processBatch()

        do {
          let lastKnownServerRecords = try await syncEngine.metadatabase.read { db in
            try SyncMetadata
              .order(by: \.recordName)
              .select(\._lastKnownServerRecordAllFields)
              .fetchAll(db)
          }
          assertInlineSnapshot(of: lastKnownServerRecords, as: .customDump) {
            """
            [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:reminders/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "reminders",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                id🗓️: 0,
                isCompleted: 1,
                isCompleted🗓️: 1,
                newField: "Hello world! 🌎🌎🌎",
                newField🗓️: 0,
                remindersListID: "00000000-0000-0000-0000-000000000001",
                remindersListID🗓️: 0,
                title: "Get milk",
                title🗓️: 0,
                🗓️: 1
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                id🗓️: 0,
                title: "Personal",
                title🗓️: 0,
                🗓️: 0
              )
            ]
            """
          }
        }
      }
    }
  }
}
