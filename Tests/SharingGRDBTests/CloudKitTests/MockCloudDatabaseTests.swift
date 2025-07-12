import CloudKit
import ConcurrencyExtras
import CustomDump
import InlineSnapshotTesting
import OrderedCollections
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class MockCloudDatabaseTests: BaseCloudKitTests, @unchecked Sendable {
    @Dependency(\.date.now) var now

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func saveTransaction_ChildBeforeParent() async throws {
      let parent = CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))
      let child = CKRecord(recordType: "B", recordID: CKRecord.ID(recordName: "B"))
      child.parent = CKRecord.Reference(record: parent, action: .none)

      await syncEngine.modifyRecords(scope: .private, saving: [child, parent])

      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(A/_defaultZone/__defaultOwner__),
                recordType: "A",
                parent: nil,
                share: nil
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(B/_defaultZone/__defaultOwner__),
                recordType: "B",
                parent: CKReference(recordID: CKRecord.ID(A/_defaultZone/__defaultOwner__)),
                share: nil
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
    @Test func deleteTransaction_ParentBeforeChild() async throws {
      let parent = CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))
      let child = CKRecord(recordType: "B", recordID: CKRecord.ID(recordName: "B"))
      child.parent = CKRecord.Reference(record: parent, action: .none)

      await syncEngine.modifyRecords(scope: .private, saving: [child, parent])
      await syncEngine.modifyRecords(scope: .private, deleting: [parent.recordID, child.recordID])

      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
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
  }
}
