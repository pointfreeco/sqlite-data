#if canImport(CloudKit)
  import CloudKit
  import Observation
  import SQLiteData
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class PendingChangeCountsTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func counts() throws {
        let privateSave = CKRecord.ID(recordName: "private-save")
        let privateDelete = CKRecord.ID(recordName: "private-delete")
        let sharedSave = CKRecord.ID(recordName: "shared-save")
        let zone = CKRecordZone(zoneName: "zone")

        syncEngine.private.state.add(
          pendingRecordZoneChanges: [.saveRecord(privateSave), .deleteRecord(privateDelete)]
        )
        syncEngine.shared.state.add(pendingRecordZoneChanges: [.saveRecord(sharedSave)])
        syncEngine.private.state.add(pendingDatabaseChanges: [.saveZone(zone)])
        syncEngine.shared.state.add(pendingDatabaseChanges: [.deleteZone(zone.zoneID)])

        let counts = try #require(syncEngine.pendingChangeCounts)
        #expect(counts.recordSaveCount == 2)
        #expect(counts.recordDeleteCount == 1)
        #expect(counts.databaseChangeCount == 2)

        syncEngine.private.state.assertPendingRecordZoneChanges([
          .saveRecord(privateSave), .deleteRecord(privateDelete),
        ])
        syncEngine.shared.state.assertPendingRecordZoneChanges([.saveRecord(sharedSave)])
        syncEngine.private.state.assertPendingDatabaseChanges([.saveZone(zone)])
        syncEngine.shared.state.assertPendingDatabaseChanges([.deleteZone(zone.zoneID)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func observation() async {
        await confirmation { changed in
          withObservationTracking {
            _ = syncEngine.pendingChangeCounts
          } onChange: {
            changed()
          }
          syncEngine.stop()
        }

        #expect(syncEngine.pendingChangeCounts == nil)
      }
    }
  }
#endif
