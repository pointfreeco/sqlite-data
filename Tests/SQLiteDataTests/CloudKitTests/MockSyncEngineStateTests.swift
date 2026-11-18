#if canImport(CloudKit)
  import CloudKit
  import SQLiteData
  import Testing

  @Suite struct MockSyncEngineStateTests {
    @Suite struct PendingRecordZoneChanges {
      let idA = CKRecord.ID(recordName: "A")
      let idB = CKRecord.ID(recordName: "B")

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `same change is deduplicated`() {
        let state = MockSyncEngineState()
        state.add(pendingRecordZoneChanges: [.saveRecord(idA)])
        state.add(pendingRecordZoneChanges: [.saveRecord(idA)])
        #expect(state.pendingRecordZoneChanges == [.saveRecord(idA)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `delete supersedes save`() {
        let state = MockSyncEngineState()
        state.add(pendingRecordZoneChanges: [.saveRecord(idA)])
        state.add(pendingRecordZoneChanges: [.deleteRecord(idA)])
        #expect(state.pendingRecordZoneChanges == [.deleteRecord(idA)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `save supersedes delete`() {
        let state = MockSyncEngineState()
        state.add(pendingRecordZoneChanges: [.deleteRecord(idA)])
        state.add(pendingRecordZoneChanges: [.saveRecord(idA)])
        #expect(state.pendingRecordZoneChanges == [.saveRecord(idA)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `last change wins`() {
        let state = MockSyncEngineState()
        state.add(pendingRecordZoneChanges: [.deleteRecord(idA)])
        state.add(pendingRecordZoneChanges: [.saveRecord(idA)])
        state.add(pendingRecordZoneChanges: [.deleteRecord(idA)])
        #expect(state.pendingRecordZoneChanges == [.deleteRecord(idA)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `superseding a change does not affect other records`() {
        let state = MockSyncEngineState()
        state.add(pendingRecordZoneChanges: [.saveRecord(idA), .saveRecord(idB)])
        state.add(pendingRecordZoneChanges: [.deleteRecord(idA)])
        #expect(Set(state.pendingRecordZoneChanges) == [.deleteRecord(idA), .saveRecord(idB)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `removing a superseded change keeps the current change`() {
        let state = MockSyncEngineState()
        state.add(pendingRecordZoneChanges: [.saveRecord(idA)])
        state.add(pendingRecordZoneChanges: [.deleteRecord(idA)])
        state.remove(pendingRecordZoneChanges: [.saveRecord(idA)])
        #expect(state.pendingRecordZoneChanges == [.deleteRecord(idA)])
      }
    }

    @Suite struct PendingDatabaseChanges {
      let zoneA = CKRecordZone(zoneName: "A")
      let zoneB = CKRecordZone(zoneName: "B")

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `same change is deduplicated`() {
        let state = MockSyncEngineState()
        state.add(pendingDatabaseChanges: [.saveZone(zoneA)])
        state.add(pendingDatabaseChanges: [.saveZone(zoneA)])
        #expect(state.pendingDatabaseChanges == [.saveZone(zoneA)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `delete supersedes save`() {
        let state = MockSyncEngineState()
        state.add(pendingDatabaseChanges: [.saveZone(zoneA)])
        state.add(pendingDatabaseChanges: [.deleteZone(zoneA.zoneID)])
        #expect(state.pendingDatabaseChanges == [.deleteZone(zoneA.zoneID)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `save supersedes delete`() {
        let state = MockSyncEngineState()
        state.add(pendingDatabaseChanges: [.deleteZone(zoneA.zoneID)])
        state.add(pendingDatabaseChanges: [.saveZone(zoneA)])
        #expect(state.pendingDatabaseChanges == [.saveZone(zoneA)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `last change wins`() {
        let state = MockSyncEngineState()
        state.add(pendingDatabaseChanges: [.deleteZone(zoneA.zoneID)])
        state.add(pendingDatabaseChanges: [.saveZone(zoneA)])
        state.add(pendingDatabaseChanges: [.deleteZone(zoneA.zoneID)])
        #expect(state.pendingDatabaseChanges == [.deleteZone(zoneA.zoneID)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `superseding a change does not affect other zones`() {
        let state = MockSyncEngineState()
        state.add(pendingDatabaseChanges: [.saveZone(zoneA), .saveZone(zoneB)])
        state.add(pendingDatabaseChanges: [.deleteZone(zoneA.zoneID)])
        #expect(Set(state.pendingDatabaseChanges) == [.deleteZone(zoneA.zoneID), .saveZone(zoneB)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func `removing a superseded change keeps the current change`() {
        let state = MockSyncEngineState()
        state.add(pendingDatabaseChanges: [.saveZone(zoneA)])
        state.add(pendingDatabaseChanges: [.deleteZone(zoneA.zoneID)])
        state.remove(pendingDatabaseChanges: [.saveZone(zoneA)])
        #expect(state.pendingDatabaseChanges == [.deleteZone(zoneA.zoneID)])
      }
    }
  }
#endif
