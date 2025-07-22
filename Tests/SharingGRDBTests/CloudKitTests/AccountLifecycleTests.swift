import CloudKit
import CustomDump
import Foundation
import InlineSnapshotTesting
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class AccountLifecycleTests: BaseCloudKitTests, @unchecked Sendable {
    @Test func signOutClearsUserDatabaseAndMetadatabase() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
          RemindersListPrivate(id: 1, remindersListID: 1)
          UnsyncedModel(id: 1)
        }
      }
      await syncEngine.processPendingRecordZoneChanges(scope: .private)

      await syncEngine.handleEvent(
        .accountChange(changeType: .signOut(previousUser: previousUserRecordID)),
        syncEngine: syncEngine.private
      )
      await syncEngine.handleEvent(
        .accountChange(changeType: .signOut(previousUser: previousUserRecordID)),
        syncEngine: syncEngine.shared
      )

      try {
        try userDatabase.userRead { db in
          try #expect(RemindersList.count().fetchOne(db) == 0)
          try #expect(Reminder.count().fetchOne(db) == 0)
          try #expect(RemindersListPrivate.count().fetchOne(db) == 0)
          try #expect(UnsyncedModel.count().fetchOne(db) == 1)
          try #expect(SyncMetadata.count().fetchOne(db) == 0)
        }
      }()
    }

    @Test func signInUploadsLocalRecordsToCloudKit() async throws {
      await syncEngine.handleEvent(
        .accountChange(changeType: .signOut(previousUser: previousUserRecordID)),
        syncEngine: syncEngine.private
      )
      await syncEngine.handleEvent(
        .accountChange(changeType: .signOut(previousUser: previousUserRecordID)),
        syncEngine: syncEngine.shared
      )
      container._accountStatus.withValue { $0 = .noAccount }

      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
          RemindersListPrivate(id: 1, remindersListID: 1)
          UnsyncedModel(id: 1)
        }
      }
      await syncEngine.processPendingRecordZoneChanges(scope: .private)

      try {
        try userDatabase.userRead { db in
          try #expect(RemindersList.count().fetchOne(db) == 1)
          try #expect(Reminder.count().fetchOne(db) == 1)
          try #expect(RemindersListPrivate.count().fetchOne(db) == 1)
          try #expect(UnsyncedModel.count().fetchOne(db) == 1)
          try #expect(SyncMetadata.count().fetchOne(db) == 1)
        }
      }()
    }
  }
}

private let previousUserRecordID = CKRecord.ID(
  recordName: "previousUser"
)
private let currentUserRecordID = CKRecord.ID(
  recordName: "previousUser"
)
