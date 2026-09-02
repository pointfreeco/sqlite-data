#if canImport(CloudKit)
  import CloudKit
  import Observation
  import SQLiteData
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class PendingChangeCountsTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func counts() {
        let privateSave = CKRecord.ID(recordName: "private-save")
        let privateDelete = CKRecord.ID(recordName: "private-delete")
        let sharedSave = CKRecord.ID(recordName: "shared-save")
        let zone = CKRecordZone(zoneName: "zone")
        let privateState = syncEngine.private.state
        let sharedState = syncEngine.shared.state

        privateState.add(
          pendingRecordZoneChanges: [.saveRecord(privateSave), .deleteRecord(privateDelete)]
        )
        sharedState.add(pendingRecordZoneChanges: [.saveRecord(sharedSave)])
        privateState.add(pendingDatabaseChanges: [.saveZone(zone)])
        sharedState.add(pendingDatabaseChanges: [.deleteZone(zone.zoneID)])

        let counts = syncEngine.pendingChangeCounts
        #expect(counts.recordSaveCount == 2)
        #expect(counts.recordDeleteCount == 1)
        #expect(counts.databaseChangeCount == 2)

        syncEngine.stop()
        #expect(syncEngine.pendingChangeCounts == counts)

        privateState.assertPendingRecordZoneChanges([
          .saveRecord(privateSave), .deleteRecord(privateDelete),
        ])
        sharedState.assertPendingRecordZoneChanges([.saveRecord(sharedSave)])
        privateState.assertPendingDatabaseChanges([.saveZone(zone)])
        sharedState.assertPendingDatabaseChanges([.deleteZone(zone.zoneID)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func observation() async {
        let counts = syncEngine.pendingChangeCounts
        await confirmation { changed in
          withObservationTracking {
            _ = syncEngine.pendingChangeCounts
          } onChange: {
            changed()
          }
          syncEngine.stop()
        }

        #expect(syncEngine.pendingChangeCounts == counts)
      }
    }
  }
#endif
