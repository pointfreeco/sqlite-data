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
    }
  }
#endif
