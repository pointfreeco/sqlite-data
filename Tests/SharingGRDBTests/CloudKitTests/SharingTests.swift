import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  final class SharingTests: BaseCloudKitTests, @unchecked Sendable {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareNonRootRecord() async throws {
      let reminder = Reminder(id: UUID(1), title: "Groceries", remindersListID: UUID(1))
      let user = User(id: UUID(1))
      try await database.write { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          reminder
          user
        }
      }
      privateSyncEngine.state.assertPendingRecordZoneChanges([
        .saveRecord(RemindersList.recordID(for: UUID(1))),
        .saveRecord(Reminder.recordID(for: UUID(1))),
        .saveRecord(User.recordID(for: UUID(1))),
      ])

      await #expect(throws: SyncEngine.RecordMustBeRoot.self) {
        _ = try await self.syncEngine.share(record: reminder, configure: { _ in })
      }
      await #expect(throws: SyncEngine.RecordMustBeRoot.self) {
        _ = try await self.syncEngine.share(record: user, configure: { _ in })
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func shareUnrecognizedTable() async throws {
      await #expect(throws: SyncEngine.UnrecognizedTable.self) {
        _ = try await self.syncEngine.share(
          record: NonSyncedTable(id: UUID()),
          configure: { _ in }
        )
      }
    }
  }
}

    // TODO: Assert on Metadata.parentRecordName when create new reminders in a shared list

@Table fileprivate struct NonSyncedTable {
  let id: UUID
}
