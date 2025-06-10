import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  final class MetadataTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func parentRecordName() throws {
      try database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          RemindersList(id: UUID(2), title: "Work")
          Reminder(id: UUID(3), title: "Groceries", remindersListID: UUID(1))
        }
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(1))),
        .saveRecord(CKRecord.ID(UUID(2))),
        .saveRecord(CKRecord.ID(UUID(3))),
      ])

      try database.write { db in
        let reminderMetadata = try #require(
          try Metadata
            .find(UUID(3))
            .fetchOne(db)
        )
        #expect(reminderMetadata.parentRecordName == UUID(1).uuidString)
      }

      try database.write { db in
        try Reminder.find(UUID(3))
          .update { $0.remindersListID = UUID(2) }
          .execute(db)
      }
      try database.write { db in
        let reminderMetadata = try #require(
          try Metadata
            .find(UUID(3))
            .fetchOne(db)
        )
        #expect(reminderMetadata.parentRecordName == UUID(2).uuidString)
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(CKRecord.ID(UUID(3))),
      ])
    }
  }
}
