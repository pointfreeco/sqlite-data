#if canImport(CloudKit)
  import CloudKit
  import SQLiteData
  import Testing

  @Suite struct MockSyncEngineStateTests {
    let recordIDa = CKRecord.ID(recordName: "A")
    let recordIDb = CKRecord.ID(recordName: "B")
    let zoneIDa = CKRecordZone.ID(zoneName: "A", ownerName: CKCurrentUserDefaultName)
    let zoneIDb = CKRecordZone.ID(zoneName: "B", ownerName: CKCurrentUserDefaultName)

    @Suite struct PendingRecordZoneChanges {
      let state = MockSyncEngineState()
      let idA = CKRecord.ID(recordName: "A")
      let idB = CKRecord.ID(recordName: "B")

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func sameType_isDeduplicatedAtOriginalPosition() {
        state.add(pendingRecordZoneChanges: [.saveRecord(idA), .saveRecord(idB)])
        state.add(pendingRecordZoneChanges: [.saveRecord(idA)])
        #expect(state.pendingRecordZoneChanges == [.saveRecord(idA), .saveRecord(idB)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func saveThenDelete_deleteSupersedes() {
        state.add(pendingRecordZoneChanges: [.saveRecord(idA)])
        state.add(pendingRecordZoneChanges: [.deleteRecord(idA)])
        #expect(state.pendingRecordZoneChanges == [.deleteRecord(idA)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteThenSave_saveSupersedes() {
        state.add(pendingRecordZoneChanges: [.deleteRecord(idA)])
        state.add(pendingRecordZoneChanges: [.saveRecord(idA)])
        #expect(state.pendingRecordZoneChanges == [.saveRecord(idA)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteThenSaveThenDelete_lastDeleteWins() {
        state.add(pendingRecordZoneChanges: [.deleteRecord(idA)])
        state.add(pendingRecordZoneChanges: [.saveRecord(idA)])
        state.add(pendingRecordZoneChanges: [.deleteRecord(idA)])
        #expect(state.pendingRecordZoneChanges == [.deleteRecord(idA)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func crossTypeSupersession_doesNotAffectOtherRecords() {
        state.add(pendingRecordZoneChanges: [.saveRecord(idA), .saveRecord(idB)])
        state.add(pendingRecordZoneChanges: [.deleteRecord(idA)])
        #expect(state.pendingRecordZoneChanges == [.saveRecord(idB), .deleteRecord(idA)])
      }
    }

    @Suite struct PendingDatabaseChanges {
      let state = MockSyncEngineState()
      let zoneA = CKRecordZone(zoneName: "A")
      let zoneB = CKRecordZone(zoneName: "B")
      var zoneAID: CKRecordZone.ID { zoneA.zoneID }
      var zoneBID: CKRecordZone.ID { zoneB.zoneID }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func sameType_isDeduplicatedAtOriginalPosition() {
        state.add(pendingDatabaseChanges: [.saveZone(zoneA), .saveZone(zoneB)])
        state.add(pendingDatabaseChanges: [.saveZone(zoneA)])
        #expect(state.pendingDatabaseChanges == [.saveZone(zoneA), .saveZone(zoneB)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func saveThenDelete_deleteSupersedes() {
        state.add(pendingDatabaseChanges: [.saveZone(zoneA)])
        state.add(pendingDatabaseChanges: [.deleteZone(zoneAID)])
        #expect(state.pendingDatabaseChanges == [.deleteZone(zoneAID)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteThenSave_saveSupersedes() {
        state.add(pendingDatabaseChanges: [.deleteZone(zoneAID)])
        state.add(pendingDatabaseChanges: [.saveZone(zoneA)])
        #expect(state.pendingDatabaseChanges == [.saveZone(zoneA)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func deleteThenSaveThenDelete_lastDeleteWins() {
        state.add(pendingDatabaseChanges: [.deleteZone(zoneAID)])
        state.add(pendingDatabaseChanges: [.saveZone(zoneA)])
        state.add(pendingDatabaseChanges: [.deleteZone(zoneAID)])
        #expect(state.pendingDatabaseChanges == [.deleteZone(zoneAID)])
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func crossTypeSupersession_doesNotAffectOtherZones() {
        state.add(pendingDatabaseChanges: [.saveZone(zoneA), .saveZone(zoneB)])
        state.add(pendingDatabaseChanges: [.deleteZone(zoneAID)])
        #expect(state.pendingDatabaseChanges == [.saveZone(zoneB), .deleteZone(zoneAID)])
      }
    }
  }
#endif
