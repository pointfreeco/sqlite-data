#if canImport(CloudKit)
  import Clocks
  import CloudKit
  import ConcurrencyExtras
  import Dependencies
  import SQLiteData
  import Testing
  import TestLocals

  extension BaseCloudKitTests {
    @MainActor
    @Suite
    final class MockCloudDatabaseBatchTests: BaseCloudKitTests, @unchecked Sendable {
      @Test func basics() async throws {
        let records = (1...199).map { index in
          CKRecord(
            recordType: "A",
            recordID: CKRecord.ID(
              recordName: "\(index)",
              zoneID: SyncEngine.defaultTestZone.zoneID
            )
          )
        }

        _ = try syncEngine.private.database.modifyRecords(saving: records)
        var counts: [Int] = []
        try await syncEngine.private.database.records(for: records.map(\.recordID)) { result in
          counts.append(result.count)
        }
        #expect(counts == [150, 49])
      }
    }
  }
#endif
