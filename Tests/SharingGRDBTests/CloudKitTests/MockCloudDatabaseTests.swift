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
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteTransaction_ParentBeforeChild() async throws {
      let parent = CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))
      let child = CKRecord(recordType: "B", recordID: CKRecord.ID(recordName: "B"))
      child.parent = CKRecord.Reference(record: parent, action: .none)

      await syncEngine.modifyRecords(scope: .private, saving: [child, parent])
      await syncEngine.modifyRecords(scope: .private, deleting: [parent.recordID, child.recordID])
    }
  }
}
