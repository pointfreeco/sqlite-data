import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class MetadataTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func parentRecordName() throws {
      try database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          RemindersList(id: UUID(2), title: "Work")
          Reminder(id: UUID(1), title: "Groceries", remindersListID: UUID(1))
        }
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1))),
        .saveRecord(RemindersList.recordID(for: UUID(2))),
        .saveRecord(Reminder.recordID(for: UUID(1))),
      ])

      try database.write { db in
        let reminderMetadata = try #require(
          try SyncMetadata
            .find(Reminder.recordName(for: UUID(1)))
            .fetchOne(db)
        )
        #expect(reminderMetadata.parentRecordName == RemindersList.recordName(for: UUID(1)))
      }

      try database.write { db in
        try Reminder.find(UUID(1))
          .update { $0.remindersListID = UUID(2) }
          .execute(db)
      }
      try database.write { db in
        let reminderMetadata = try #require(
          try SyncMetadata
            .find(Reminder.recordName(for: UUID(1)))
            .fetchOne(db)
        )
        #expect(reminderMetadata.parentRecordName == RemindersList.recordName(for: UUID(2)))
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(Reminder.recordID(for: UUID(1))),
      ])
    }
  }
}
