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
    func fetchReminderListMetadata(_ recordID: RemindersList.ID) async throws -> SyncMetadata? {
      try await self.syncEngine.metadatabase.read {
        try SyncMetadata.find(RemindersList.recordID(for: recordID)).fetchOne($0)
      }
    }
    
    @MainActor
    func fetchReminderMetadata(_ recordID: Reminder.ID) async throws -> SyncMetadata? {
      try await self.syncEngine.metadatabase.read {
        try SyncMetadata.find(Reminder.recordID(for: recordID)).fetchOne($0)
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    func expectMetadataServerRecord(
      _ metadata: SyncMetadata,
      matchesContainerRecord recordID: CKRecord.ID,
      fileID: StaticString = #fileID,
      filePath: StaticString = #filePath,
      line: UInt = #line,
      column: UInt = #column
    ) throws {
      let containerRecord = try container.privateCloudDatabase.record(for: recordID)
      var containerRecordDump = ""
      var metadataServerRecordDump = ""
      customDump(containerRecord, to: &containerRecordDump)
      customDump(metadata._lastKnownServerRecordAllFields, to: &metadataServerRecordDump)
      expectNoDifference(
        metadataServerRecordDump, containerRecordDump,
        fileID: fileID, filePath: filePath, line: line, column: column
      )
    }
    
    @MainActor
    final class ChangeSupersessionTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func insertThenDelete_deletes() async throws {
        try await userDatabase.userWrite { db in
          try RemindersList.insert { RemindersList(id: 1, title: "Personal") }.execute(db)
          try RemindersList.find(1).delete().execute(db)
        }
        #expect(try #require(await fetchReminderListMetadata(1))._pendingStatus == .deleted)

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        
        #expect(try await fetchReminderListMetadata(1) == nil)

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
        #expect(try #require(await fetchReminderListMetadata(1))._pendingStatus == .deleted)

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        
        #expect(try await fetchReminderListMetadata(1) == nil)

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
        
        #expect(try #require(await fetchReminderListMetadata(1))._pendingStatus == .deleted)
        
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        
        #expect(try await fetchReminderListMetadata(1) == nil)

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
      @Test func insertThenDeleteThenReinsert_saves() async throws {
        try await userDatabase.userWrite { db in
          try RemindersList.insert { RemindersList(id: 1, title: "Original") }.execute(db)
          try RemindersList.find(1).delete().execute(db)
          try RemindersList.insert { RemindersList(id: 1, title: "Reinserted") }.execute(db)
        }
        #expect(try #require(await fetchReminderListMetadata(1))._pendingStatus == .reinserted)

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        
        let metadata = try #require(await fetchReminderListMetadata(1))
        #expect(metadata._pendingStatus == nil)
        try expectMetadataServerRecord(metadata, matchesContainerRecord: RemindersList.recordID(for: 1))

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
                  title: "Reinserted"
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

          #expect(try #require(await fetchReminderListMetadata(1))._pendingStatus == .reinserted)

          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        }

        let metadata = try #require(await fetchReminderListMetadata(1))
        #expect(metadata._pendingStatus == nil)

        try expectMetadataServerRecord(metadata, matchesContainerRecord: RemindersList.recordID(for: 1))

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
            
            #expect(try #require(await fetchReminderListMetadata(1))._pendingStatus == .reinserted)

            try await syncEngine.processPendingRecordZoneChanges(scope: .private)
          }
        }
        
        let metadata = try #require(await fetchReminderListMetadata(1))
        #expect(metadata._pendingStatus == nil)

        try expectMetadataServerRecord(metadata, matchesContainerRecord: RemindersList.recordID(for: 1))

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
      @Test(.printTimestamps) func deleteThenReinsertThenUpdateInSeparateWrites_allFieldsSavedWithLatestTimestamp()
        async throws
      {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            Reminder(id: 1, dueDate: Date(timeIntervalSince1970: Double(0)), title: "Get milk", remindersListID: 1)
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try Reminder.find(1).delete().execute(db)
          }
          try await withDependencies {
            $0.currentTime.now += 1
          } operation: {
            try await userDatabase.userWrite { db in
              try Reminder.insert {
                Reminder(id: 1, dueDate: Date(timeIntervalSince1970: Double(30)), title: "(Reinserted) Get milk", remindersListID: 1)
              }.execute(db)
            }
            try await withDependencies {
              $0.currentTime.now += 1
            } operation: {
              try await userDatabase.userWrite { db in
                try Reminder.update {
                  $0.title = "(Updated) Get milk"
                }.execute(db)
              }
              
              #expect(try #require(await fetchReminderMetadata(1))._pendingStatus == .reinserted)

              try await syncEngine.processPendingRecordZoneChanges(scope: .private)
            }
          }
        }
        
        let metadata = try #require(await fetchReminderMetadata(1))
        #expect(metadata._pendingStatus == nil)

        try expectMetadataServerRecord(metadata, matchesContainerRecord: Reminder.recordID(for: 1))

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:reminders/zone/__defaultOwner__),
                  recordType: "reminders",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                  share: nil,
                  dueDate: Date(1970-01-01T00:00:30.000Z),
                  dueDate🗓️: 3,
                  id: 1,
                  id🗓️: 3,
                  isCompleted: 0,
                  isCompleted🗓️: 3,
                  priority🗓️: 3,
                  remindersListID: 1,
                  remindersListID🗓️: 3,
                  title: "(Updated) Get milk",
                  title🗓️: 3,
                  🗓️: 3
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  id🗓️: 0,
                  title: "Personal",
                  title🗓️: 0,
                  🗓️: 0
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
          
          #expect(try #require(await fetchReminderListMetadata(1))._pendingStatus == .reinserted)

          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        }
        
        let metadata = try #require(await fetchReminderListMetadata(1))
        #expect(metadata._pendingStatus == nil)

        try expectMetadataServerRecord(metadata, matchesContainerRecord: RemindersList.recordID(for: 1))

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
          
          #expect(try #require(await fetchReminderListMetadata(1))._pendingStatus == .reinserted)

          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        }
        
        let metadata = try #require(await fetchReminderListMetadata(1))
        #expect(metadata._pendingStatus == nil)

        try expectMetadataServerRecord(metadata, matchesContainerRecord: RemindersList.recordID(for: 1))

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
          
          #expect(try #require(await fetchReminderListMetadata(1))._pendingStatus == .reinserted)

          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        }
        
        let metadata = try #require(await fetchReminderListMetadata(1))
        #expect(metadata._pendingStatus == nil)

        try expectMetadataServerRecord(metadata, matchesContainerRecord: RemindersList.recordID(for: 1))

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
          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
          
          try await withDependencies {
            $0.currentTime.now += 1
          } operation: {
            try await userDatabase.userWrite { db in
              try RemindersList.find(1).delete().execute(db)
              try RemindersList.insert { RemindersList(id: 1, title: "Cycle2") }.execute(db)
            }
            
            #expect(try #require(await fetchReminderListMetadata(1))._pendingStatus == .reinserted)
            
            try await syncEngine.processPendingRecordZoneChanges(scope: .private)
          }
        }
        
        let metadata = try #require(await fetchReminderListMetadata(1))
        #expect(metadata._pendingStatus == nil)

        try expectMetadataServerRecord(metadata, matchesContainerRecord: RemindersList.recordID(for: 1))

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

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test(.printTimestamps) func reinsertedRecord_staleServerUpdate_localWins() async throws {
        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Original") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
            try RemindersList.insert { RemindersList(id: 1, title: "Reinserted") }.execute(db)
          }
          
          #expect(try #require(await fetchReminderListMetadata(1))._pendingStatus == .reinserted)

          let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
          record.setValue("Server", forKey: "title", at: 0)
          try await syncEngine.modifyRecords(scope: .private, saving: [record]).notify()
          
          let metadata = try #require(await fetchReminderListMetadata(1))
          #expect(metadata._pendingStatus == nil)
          #expect(metadata.userModificationTime == 1)

          let row = try await userDatabase.read { db in
            try RemindersList.find(1).fetchOne(db)
          }
          #expect(row?.title == "Reinserted")

          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        }
        
        let metadata = try #require(await fetchReminderListMetadata(1))
        #expect(metadata._pendingStatus == nil)
        #expect(metadata.userModificationTime == 1)

        try expectMetadataServerRecord(metadata, matchesContainerRecord: RemindersList.recordID(for: 1))

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
                  id🗓️: 0,
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
      @Test(.printTimestamps) func reinsertedRecord_freshServerUpdate_serverWins() async throws {
        try await userDatabase.userWrite { db in
          try db.seed { RemindersList(id: 1, title: "Original") }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersList.find(1).delete().execute(db)
            try RemindersList.insert { RemindersList(id: 1, title: "Reinserted") }.execute(db)
          }
          
          #expect(try #require(await fetchReminderListMetadata(1))._pendingStatus == .reinserted)

          let record = try syncEngine.private.database.record(for: RemindersList.recordID(for: 1))
          record.setValue("Server", forKey: "title", at: 2)
          try await syncEngine.modifyRecords(scope: .private, saving: [record]).notify()
          
          #expect(try #require(await fetchReminderListMetadata(1))._pendingStatus == nil)

          let row = try await userDatabase.read { db in
            try RemindersList.find(1).fetchOne(db)
          }
          #expect(row?.title == "Server")

          try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        }
        
        let metadata = try #require(await fetchReminderListMetadata(1))
        #expect(metadata._pendingStatus == nil)

        try expectMetadataServerRecord(metadata, matchesContainerRecord: RemindersList.recordID(for: 1))

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
                  id🗓️: 0,
                  title: "Server",
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


