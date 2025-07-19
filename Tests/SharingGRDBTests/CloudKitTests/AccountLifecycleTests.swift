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
    @Test func signOut() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: 1, title: "Personal")
          Reminder(id: 1, title: "Get milk", remindersListID: 1)
          
        }
      }

      await syncEngine.handleEvent(
        .accountChange(changeType: .signOut(previousUser: previousUserRecordID)),
        syncEngine: syncEngine.private
      )
      await syncEngine.handleEvent(
        .accountChange(changeType: .signOut(previousUser: previousUserRecordID)),
        syncEngine: syncEngine.shared
      )
    }
  }
}

private let previousUserRecordID = CKRecord.ID(
  recordName: "previousUser"
)
private let currentUserRecordID = CKRecord.ID(
  recordName: "previousUser"
)
