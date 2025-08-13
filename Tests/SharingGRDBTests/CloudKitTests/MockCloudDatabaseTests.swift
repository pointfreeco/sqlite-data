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
    init() async throws {
      try await super.init()
      let (saveZoneResults, _) = try syncEngine.private.database.modifyRecordZones(
        saving: [
          CKRecordZone(
            zoneID: CKRecord(recordType: "A\(Int.random(in: 1...999_999_999))").recordID.zoneID
          )
        ],
        deleting: []
      )
      #expect(saveZoneResults.allSatisfy({ (try? $1.get()) != nil }))
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func fetchRecordInUnknownZone() async throws {
      let error = #expect(throws: CKError.self) {
        try self.syncEngine.private.database.record(
          for: CKRecord.ID(
            recordName: "A",
            zoneID: CKRecordZone.ID(zoneName: "zone")
          )
        )
      }
      #expect(error == CKError(.zoneNotFound))
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func fetchUnknownRecord() async throws {
      let error = #expect(throws: CKError.self) {
        try self.syncEngine.private.database.record(for: CKRecord.ID(recordName: "A"))
      }
      #expect(error == CKError(.unknownItem))
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func saveTransaction_ChildBeforeParent() async throws {
      let parent = CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))
      let child = CKRecord(recordType: "B", recordID: CKRecord.ID(recordName: "B"))
      child.parent = CKRecord.Reference(record: parent, action: .none)

      let (saveRecordResults, _) = try syncEngine.private.database.modifyRecords(
        saving: [child, parent],
        deleting: []
      )
      #expect(saveRecordResults.allSatisfy({ (try? $1.get()) != nil }))

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
    @Test func saveTransaction_ChildNoParent() async throws {
      let parent = CKRecord(recordType: "Parent", recordID: CKRecord.ID(recordName: "Parent"))
      let child = CKRecord(recordType: "Child", recordID: CKRecord.ID(recordName: "Child"))
      child.parent = CKRecord.Reference(record: parent, action: .none)

      let (saveRecordResults, _) = try syncEngine.private.database.modifyRecords(
        saving: [child],
        deleting: []
      )
      let error = #expect(throws: CKError.self) {
        try saveRecordResults[child.recordID]?.get()
      }
      #expect(error == CKError(.referenceViolation))

      try await syncEngine.modifyRecords(scope: .private, saving: [child]).notify()

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

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func saveInUnknownZone() async throws {
      let record = CKRecord(
        recordType: "Record",
        recordID: CKRecord.ID(recordName: "Record", zoneID: CKRecordZone.ID(zoneName: "zone"))
      )

      let (saveRecordResults, _) = try syncEngine.private.database.modifyRecords(
        saving: [record],
        deleting: []
      )
      let error = #expect(throws: CKError.self) {
        try saveRecordResults[record.recordID]?.get()
      }
      #expect(error == CKError(.zoneNotFound))

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

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteTransaction_ParentBeforeChild() async throws {
      let parent = CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))
      let child = CKRecord(recordType: "B", recordID: CKRecord.ID(recordName: "B"))
      child.parent = CKRecord.Reference(record: parent, action: .none)

      let _ = try syncEngine.private.database.modifyRecords(saving: [child, parent])
      let (_, deleteResults) = try syncEngine.private.database.modifyRecords(
        deleting: [parent.recordID, child.recordID]
      )
      #expect(deleteResults.allSatisfy({ (try? $1.get()) != nil }))

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

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteUnknownRecord() async throws {
      let record = CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))

      let (_, deleteResults) = try syncEngine.private.database.modifyRecords(
        deleting: [record.recordID]
      )
      #expect(deleteResults.allSatisfy({ (try? $1.get()) != nil }))

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

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteRecordInUnknownZone() async throws {
      let record = CKRecord(
        recordType: "A",
        recordID: CKRecord.ID(recordName: "A", zoneID: CKRecordZone.ID(zoneName: "zone"))
      )

      let (_, deleteResults) = try syncEngine.private.database.modifyRecords(
        deleting: [record.recordID]
      )
      let error = #expect(throws: CKError.self) {
        try deleteResults[record.recordID]?.get()
      }
      #expect(error == CKError(.zoneNotFound))

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

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func deleteTransaction_DeleteParentButNotChild() async throws {
      let parent = CKRecord(recordType: "A", recordID: CKRecord.ID(recordName: "A"))
      let child = CKRecord(recordType: "B", recordID: CKRecord.ID(recordName: "B"))
      child.parent = CKRecord.Reference(record: parent, action: .none)

      _ = try syncEngine.private.database.modifyRecords(saving: [child, parent])
      let (_, deleteResults) = try syncEngine.private.database.modifyRecords(
        deleting: [parent.recordID]
      )
      let error = #expect(throws: CKError.self) {
        try deleteResults[CKRecord.ID(recordName: "A")]?.get()
      }
      #expect(error == CKError(.referenceViolation))

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
    @Test func deleteUnknownZone() async throws {
      let (_, deleteResults) = try syncEngine.private.database.modifyRecordZones(
        saving: [],
        deleting: [CKRecordZone.ID(zoneName: "zone")]
      )
      let error = #expect(throws: CKError.self) {
        try deleteResults[CKRecordZone.ID(zoneName: "zone")]?.get()
      }
      #expect(error == CKError(.zoneNotFound))
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func accountTemporarilyAvailable() async throws {
      container._accountStatus.withValue { $0 = .temporarilyUnavailable }
      var error = #expect(throws: CKError.self) {
        _ = try self.syncEngine.private.database.modifyRecordZones()
      }
      #expect(error == CKError(.accountTemporarilyUnavailable))
      error = #expect(throws: CKError.self) {
        _ = try self.syncEngine.private.database.modifyRecords()
      }
      #expect(error == CKError(.accountTemporarilyUnavailable))
      error = #expect(throws: CKError.self) {
        _ = try self.syncEngine.private.database.record(for: CKRecord.ID(recordName: "test"))
      }
      #expect(error == CKError(.accountTemporarilyUnavailable))
      error = await #expect(throws: CKError.self) {
        _ = try await self.syncEngine.private.database.records(for: [CKRecord.ID(recordName: "test")])
      }
      #expect(error == CKError(.accountTemporarilyUnavailable))
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func noAccount() async throws {
      container._accountStatus.withValue { $0 = .noAccount }
      var error = #expect(throws: CKError.self) {
        _ = try self.syncEngine.private.database.modifyRecordZones()
      }
      #expect(error == CKError(.notAuthenticated))
      error = #expect(throws: CKError.self) {
        _ = try self.syncEngine.private.database.modifyRecords()
      }
      #expect(error == CKError(.notAuthenticated))
      error = #expect(throws: CKError.self) {
        _ = try self.syncEngine.private.database.record(for: CKRecord.ID(recordName: "test"))
      }
      #expect(error == CKError(.notAuthenticated))
      error = await #expect(throws: CKError.self) {
        _ = try await self.syncEngine.private.database.records(for: [CKRecord.ID(recordName: "test")])
      }
      #expect(error == CKError(.notAuthenticated))
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func accountNotDetermined() async throws {
      container._accountStatus.withValue { $0 = .couldNotDetermine }
      var error = #expect(throws: CKError.self) {
        _ = try self.syncEngine.private.database.modifyRecordZones()
      }
      #expect(error == CKError(.notAuthenticated))
      error = #expect(throws: CKError.self) {
        _ = try self.syncEngine.private.database.modifyRecords()
      }
      #expect(error == CKError(.notAuthenticated))
      error = #expect(throws: CKError.self) {
        _ = try self.syncEngine.private.database.record(for: CKRecord.ID(recordName: "test"))
      }
      #expect(error == CKError(.notAuthenticated))
      error = await #expect(throws: CKError.self) {
        _ = try await self.syncEngine.private.database.records(for: [CKRecord.ID(recordName: "test")])
      }
      #expect(error == CKError(.notAuthenticated))
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func restrictedAccount() async throws {
      container._accountStatus.withValue { $0 = .restricted }
      var error = #expect(throws: CKError.self) {
        _ = try self.syncEngine.private.database.modifyRecordZones()
      }
      #expect(error == CKError(.notAuthenticated))
      error = #expect(throws: CKError.self) {
        _ = try self.syncEngine.private.database.modifyRecords()
      }
      #expect(error == CKError(.notAuthenticated))
      error = #expect(throws: CKError.self) {
        _ = try self.syncEngine.private.database.record(for: CKRecord.ID(recordName: "test"))
      }
      #expect(error == CKError(.notAuthenticated))
      error = await #expect(throws: CKError.self) {
        _ = try await self.syncEngine.private.database.records(for: [CKRecord.ID(recordName: "test")])
      }
      #expect(error == CKError(.notAuthenticated))
    }

    @Test func incorrectlyCreatingNewRecordIdentity() async throws {
      let record1 = CKRecord(recordType: "A", recordID: CKRecord.ID.init(recordName: "1"))
      _ = try syncEngine.modifyRecords(scope: .private, saving: [record1])
      let record2 = CKRecord(recordType: "A", recordID: CKRecord.ID.init(recordName: "1"))
      try withKnownIssue {
        _ = try syncEngine.modifyRecords(scope: .private, saving: [record2])
      } matching: { issue in
        issue.description == """
          Issue recorded: A new identity was created for an existing 'CKRecord' ('1'). Rather than \
          creating 'CKRecord' from scratch for an existing record, use the database to fetch the \ 
          current record.
          """
      }
    }
  }
}
