#if canImport(CloudKit)
  import Clocks
  import CloudKit
  import ConcurrencyExtras
  import InlineSnapshotTesting
  import Dependencies
  import SQLiteData
  import Testing
  import TestLocals

  extension BaseCloudKitTests {
    @MainActor
    @Suite(.taskLocal($quota, 2))
    final class MockCloudDatabaseQuotaTests: BaseCloudKitTests, @unchecked Sendable {
      @Test func basics() throws {
        var saveResults = try syncEngine.private.database.modifyRecords(
          saving: [
            CKRecord(
              recordType: "A",
              recordID: CKRecord.ID(recordName: "1", zoneID: SyncEngine.defaultTestZone.zoneID)
            ),
            CKRecord(
              recordType: "A",
              recordID: CKRecord.ID(recordName: "2", zoneID: SyncEngine.defaultTestZone.zoneID)
            ),
          ]
        )
        .saveResults
        try #expect(saveResults.values.map { try $0.get() }.count == 2)

        saveResults = try syncEngine.private.database.modifyRecords(
          saving: [
            CKRecord(
              recordType: "A",
              recordID: CKRecord.ID(recordName: "3", zoneID: SyncEngine.defaultTestZone.zoneID)
            )
          ]
        )
        .saveResults
        let error = #expect(throws: CKError.self) {
          _ = try saveResults.first?.value.get()
        }
        #expect(error?.code == .quotaExceeded)

        saveResults = try syncEngine.private.database.modifyRecords(
          saving: [
            CKRecord(
              recordType: "A",
              recordID: CKRecord.ID(recordName: "3", zoneID: SyncEngine.defaultTestZone.zoneID)
            )
          ],
          deleting: [
            CKRecord.ID(recordName: "1", zoneID: SyncEngine.defaultTestZone.zoneID)
          ]
        )
        .saveResults
        try #expect(saveResults.values.map { try $0.get() }.count == 1)
        assertInlineSnapshot(of: syncEngine.private.database, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(2/zone/__defaultOwner__),
                recordType: "A",
                parent: nil,
                share: nil
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(3/zone/__defaultOwner__),
                recordType: "A",
                parent: nil,
                share: nil
              )
            ]
          )
          """
        }
      }

      @Test(.taskLocal($quota, 10))
      func assetBytesCountTowardQuota() throws {
        let largeRecord = try record("1", assetSize: 20)
        let smallRecord = try record("2")

        let saveResults = try syncEngine.private.database.modifyRecords(
          saving: [largeRecord, smallRecord],
          atomically: false
        )
        .saveResults

        let error = #expect(throws: CKError.self) {
          _ = try saveResults[largeRecord.recordID]?.get()
        }
        #expect(error?.code == .quotaExceeded)
        #expect(throws: Never.self) {
          _ = try saveResults[smallRecord.recordID]?.get()
        }
        assertInlineSnapshot(of: syncEngine.private.database, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(2/zone/__defaultOwner__),
                recordType: "A",
                parent: nil,
                share: nil
              )
            ]
          )
          """
        }
      }

      @Test(.taskLocal($quota, 10))
      func assetBytesFitInQuota() throws {
        let record = try record("1", assetSize: 9)

        let saveResults = try syncEngine.private.database.modifyRecords(saving: [record])
          .saveResults

        #expect(throws: Never.self) {
          _ = try saveResults[record.recordID]?.get()
        }
      }

      @Test(.taskLocal($quota, 10))
      func childOfParentThatExceededQuotaHasReferenceViolation() throws {
        let parentRecord = try record("parent", assetSize: 20)
        let childRecord = try record("child")
        childRecord.parent = CKRecord.Reference(record: parentRecord, action: .none)

        let saveResults = try syncEngine.private.database.modifyRecords(
          saving: [parentRecord, childRecord],
          atomically: false
        )
        .saveResults

        let parentError = #expect(throws: CKError.self) {
          _ = try saveResults[parentRecord.recordID]?.get()
        }
        #expect(parentError?.code == .quotaExceeded)
        let childError = #expect(throws: CKError.self) {
          _ = try saveResults[childRecord.recordID]?.get()
        }
        #expect(childError?.code == .referenceViolation)
        assertInlineSnapshot(of: syncEngine.private.database, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: []
          )
          """
        }
      }

      @Test(.taskLocal($quota, 10))
      func childSavedBeforeParentThatExceededQuotaHasReferenceViolation() throws {
        let parentRecord = try record("parent", assetSize: 20)
        let childRecord = try record("child")
        childRecord.parent = CKRecord.Reference(record: parentRecord, action: .none)

        let saveResults = try syncEngine.private.database.modifyRecords(
          saving: [childRecord, parentRecord],
          atomically: false
        )
        .saveResults

        let parentError = #expect(throws: CKError.self) {
          _ = try saveResults[parentRecord.recordID]?.get()
        }
        #expect(parentError?.code == .quotaExceeded)
        let childError = #expect(throws: CKError.self) {
          _ = try saveResults[childRecord.recordID]?.get()
        }
        #expect(childError?.code == .referenceViolation)
      }

      private func record(_ recordName: String, assetSize: Int? = nil) throws -> CKRecord {
        let record = CKRecord(
          recordType: "A",
          recordID: CKRecord.ID(recordName: recordName, zoneID: SyncEngine.defaultTestZone.zoneID)
        )
        if let assetSize {
          let url = URL(fileURLWithPath: "/sqlite-data-test-assets/\(recordName)")
          try inMemoryDataManager.save(Data(repeating: 0, count: assetSize), to: url)
          record["asset"] = CKAsset(fileURL: url)
        }
        return record
      }
    }
  }
#endif
