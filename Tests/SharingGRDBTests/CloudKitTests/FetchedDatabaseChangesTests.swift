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
  @Suite
  final class FetchedDatabaseChangesTests: BaseCloudKitTests, @unchecked Sendable {
    @Test func deleteSyncEngineZone() async throws {
      try await userDatabase.write { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          RemindersList(id: 2, title: "Business")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
          Reminder(id: 2, title: "Call accountant", remindersListID: 2)
          PrivateModel(id: 1)
          PrivateModel(id: 2)
        }
      }
      await syncEngine.processBatch()

      await syncEngine.modifyRecordZones(scope: .private, deleting: [SyncEngine.defaultZone.zoneID])

      try {
        try userDatabase.read { db in
          try #expect(Reminder.all.fetchAll(db) == [])
          try #expect(RemindersList.all.fetchAll(db) == [])
        }
      }()
    }
  }
}
