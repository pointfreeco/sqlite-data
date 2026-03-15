#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import InlineSnapshotTesting
  import OrderedCollections
  import SQLiteData
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class ChangeSupersessionTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func insertThenDelete_deletes() async throws {
        try await userDatabase.userWrite { db in
          try RemindersList.insert { RemindersList(id: 1, title: "Personal") }.execute(db)
          try RemindersList.find(1).delete().execute(db)
        }

        let pending = syncEngine.private.state.pendingRecordZoneChanges
        #expect(pending == [.deleteRecord(RemindersList.recordID(for: 1))])

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container, as: .customDump) {
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
      @Test func updateThenDelete_deletes() async throws {
        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Original") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.userWrite { db in
          try RemindersList.find(1).update { $0.title = "Updated" }.execute(db)
          try RemindersList.find(1).delete().execute(db)
        }

        let pending = syncEngine.private.state.pendingRecordZoneChanges
        #expect(pending == [.deleteRecord(RemindersList.recordID(for: 1))])

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container, as: .customDump) {
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
      @Test func deleteThenReinsertThenDelete_deletes() async throws {
        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Original") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.userWrite { db in
          try RemindersList.find(1).delete().execute(db)
          try RemindersList.insert { RemindersList(id: 1, title: "Reinserted") }.execute(db)
          try RemindersList.find(1).delete().execute(db)
        }

        let pending = syncEngine.private.state.pendingRecordZoneChanges
        #expect(pending == [.deleteRecord(RemindersList.recordID(for: 1))])

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container, as: .customDump) {
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
      @Test(.printTimestamps) func deleteThenReinsertInSingleWrite_savesWithUpdatedTimestamps()
        async throws
      {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Original")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
            try RemindersList.insert { RemindersList(id: 1, title: "Reinserted") }.execute(db)
          }

          let pending = syncEngine.private.state.pendingRecordZoneChanges
          #expect(pending == [.saveRecord(RemindersList.recordID(for: 1))])

          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        }

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 1,
                  title: "Reinserted",
                  title🗓️: 1,
                  🗓️: 1
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
      @Test(.printTimestamps) func deleteThenReinsertInSeparateWrites_savesWithUpdatedTimestamps()
        async throws
      {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Original")
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
          }
          try await withDependencies {
            $0.currentTime.now += 1
          } operation: {
            try await userDatabase.userWrite { db in
              try RemindersList.insert { RemindersList(id: 1, title: "Reinserted") }.execute(db)
            }

            let pending = syncEngine.private.state.pendingRecordZoneChanges
            #expect(pending == [.saveRecord(RemindersList.recordID(for: 1))])

            try await syncEngine.processPendingRecordZoneChanges(scope: .private)
          }
        }

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 2,
                  title: "Reinserted",
                  title🗓️: 2,
                  🗓️: 2
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
      @Test(.printTimestamps) func updateThenDeleteThenReinsert_savesWithUpdatedTimestamps()
        async throws
      {
        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Original") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).update { $0.title = "Updated" }.execute(db)
            try RemindersList.find(1).delete().execute(db)
            try RemindersList.insert { RemindersList(id: 1, title: "Reinserted") }.execute(db)
          }

          let pending = syncEngine.private.state.pendingRecordZoneChanges
          #expect(pending == [.saveRecord(RemindersList.recordID(for: 1))])

          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        }

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 1,
                  title: "Reinserted",
                  title🗓️: 1,
                  🗓️: 1
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
      @Test(.printTimestamps) func deleteThenReinsertWithSameValue_savesWithUpdatedTimestamps()
        async throws
      {
        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Original") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
            try RemindersList.insert { RemindersList(id: 1, title: "Original") }.execute(db)
          }
          let pending = syncEngine.private.state.pendingRecordZoneChanges
          #expect(pending == [.saveRecord(RemindersList.recordID(for: 1))])
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        }

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 1,
                  title: "Original",
                  title🗓️: 1,
                  🗓️: 1
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
      @Test(.printTimestamps) func twoDeleteReinsertCyclesInSameWrite_savesLatestWithUpdatedTimestamps()
        async throws
      {
        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Original") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
            try RemindersList.insert { RemindersList(id: 1, title: "Middle") }.execute(db)
            try RemindersList.find(1).delete().execute(db)
            try RemindersList.insert { RemindersList(id: 1, title: "Final") }.execute(db)
          }
          let pending = syncEngine.private.state.pendingRecordZoneChanges
          #expect(pending == [.saveRecord(RemindersList.recordID(for: 1))])
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        }

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 1,
                  title: "Final",
                  title🗓️: 1,
                  🗓️: 1
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
      @Test(.printTimestamps) func twoDeleteReinsertCyclesInSeparateBatches_savesLatestWithUpdatedTimestamps()
        async throws
      {
        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Original") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
            try RemindersList.insert { RemindersList(id: 1, title: "Cycle1") }.execute(db)
          }
          let pending = syncEngine.private.state.pendingRecordZoneChanges
          #expect(pending == [.saveRecord(RemindersList.recordID(for: 1))])
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
          
          try await withDependencies {
            $0.currentTime.now += 1
          } operation: {
            try await userDatabase.userWrite { db in
              try RemindersList.find(1).delete().execute(db)
              try RemindersList.insert { RemindersList(id: 1, title: "Cycle2") }.execute(db)
            }
            let pending = syncEngine.private.state.pendingRecordZoneChanges
            #expect(pending == [.saveRecord(RemindersList.recordID(for: 1))])
            try await syncEngine.processPendingRecordZoneChanges(scope: .private)
          }
        }

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 2,
                  title: "Cycle2",
                  title🗓️: 2,
                  🗓️: 2
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
    }
  }
#endif
