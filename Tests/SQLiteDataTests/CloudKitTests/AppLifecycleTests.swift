#if canImport(CloudKit) && canImport(UIKit)
  import CloudKit
  import CustomDump
  import Foundation
  import InlineSnapshotTesting
  import SQLiteData
  import SnapshotTestingCustomDump
  import Testing
  import SQLiteDataTestSupport

  import UIKit

  extension BaseCloudKitTests {
    // TODO: WRITE MORE TESTS
    @MainActor
    @Suite
    final class AppLifecycleTests: BaseCloudKitTests, @unchecked Sendable {
      @Dependency(\.defaultNotificationCenter) var defaultNotificationCenter

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func sendChangesOnBackground() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
          }
        }
        defaultNotificationCenter.post(name: UIScene.willDeactivateNotification, object: nil)
        try await Task.sleep(for: .seconds(0.1))
        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
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
#endif
