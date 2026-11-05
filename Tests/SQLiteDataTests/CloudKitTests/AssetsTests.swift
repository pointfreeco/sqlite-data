#if canImport(CloudKit)
  import CloudKit
  import ConcurrencyExtras
  import CustomDump
  import InlineSnapshotTesting
  import OrderedCollections
  import SQLiteData
  import SQLiteDataTestSupport
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class AssetsTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func basics() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersListAsset(remindersListID: 1, coverImage: Data("image".utf8))
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersListAssets/zone/__defaultOwner__),
                  recordType: "remindersListAssets",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                  share: nil,
                  coverImage_hash: Data(32 bytes),
                  remindersListID: 1,
                  coverImage: CKAsset(
                    fileURL: URL(file:///tmp/6105d6cc76af400325e94d588ce511be5bfdbb73b437dc51eca43917d7a43e3d),
                    dataString: "image"
                  )
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: "Personal"
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

        inMemoryDataManager.storage.withValue { storage in
          let url = URL(
            string: "file:///tmp/6105d6cc76af400325e94d588ce511be5bfdbb73b437dc51eca43917d7a43e3d"
          )!
          #expect(storage[url] == Data("image".utf8))
        }

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersListAsset
              .find(1)
              .update { $0.coverImage = #bind(Data("new-image".utf8)) }
              .execute(db)
          }
        }

        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        assertInlineSnapshot(of: container, as: .customDump) {
          """
          MockCloudContainer(
            privateCloudDatabase: MockCloudDatabase(
              databaseScope: .private,
              storage: [
                [0]: CKRecord(
                  recordID: CKRecord.ID(1:remindersListAssets/zone/__defaultOwner__),
                  recordType: "remindersListAssets",
                  parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)),
                  share: nil,
                  coverImage_hash: Data(32 bytes),
                  remindersListID: 1,
                  coverImage: CKAsset(
                    fileURL: URL(file:///tmp/97e67a5645969953f1a4cfe2ea75649864ff99789189cdd3f6db03e59f8a8ebf),
                    dataString: "new-image"
                  )
                ),
                [1]: CKRecord(
                  recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__),
                  recordType: "remindersLists",
                  parent: nil,
                  share: nil,
                  id: 1,
                  title: "Personal"
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

        inMemoryDataManager.storage.withValue { storage in
          let url = URL(
            string: "file:///tmp/97e67a5645969953f1a4cfe2ea75649864ff99789189cdd3f6db03e59f8a8ebf"
          )!
          #expect(storage[url] == Data("new-image".utf8))
        }
      }

      // * Receive record with CKAsset from CloudKit
      // => Stored in database as bytes
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func receiveAsset() async throws {
        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1)
        )
        remindersListRecord.setValue("1", forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)

        let fileURL = URL(fileURLWithPath: UUID().uuidString)
        try inMemoryDataManager.save(Data("image".utf8), to: fileURL)
        let remindersListAssetRecord = CKRecord(
          recordType: RemindersListAsset.tableName,
          recordID: RemindersListAsset.recordID(for: 1)
        )
        remindersListAssetRecord.setValue("1", forKey: "id", at: now)
        remindersListAssetRecord.setAsset(CKAsset(fileURL: fileURL), forKey: "coverImage", at: now)
        remindersListAssetRecord.setValue("1", forKey: "remindersListID", at: now)
        remindersListAssetRecord.parent = CKRecord.Reference(
          record: remindersListRecord,
          action: .none
        )

        try await syncEngine.modifyRecords(
          scope: .private,
          saving: [remindersListAssetRecord, remindersListRecord]
        )
        .notify()

        try await userDatabase.read { db in
          let remindersListAsset = try #require(
            try RemindersListAsset.find(1).fetchOne(db)
          )
          #expect(remindersListAsset.coverImage == Data("image".utf8))
        }
      }

      // * Receive record with CKAsset from CloudKit when local asset exists
      // => Stored in database as bytes
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func receiveUpdatedAsset() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersListAsset(remindersListID: 1, coverImage: Data("image".utf8))
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          let fileURL = URL(fileURLWithPath: UUID().uuidString)
          try inMemoryDataManager.save(Data("new-image".utf8), to: fileURL)
          let remindersListAssetRecord = try syncEngine.private.database.record(
            for: RemindersListAsset.recordID(for: 1)
          )
          remindersListAssetRecord.setAsset(
            CKAsset(fileURL: fileURL),
            forKey: "coverImage",
            at: now
          )
          try await syncEngine.modifyRecords(
            scope: .private,
            saving: [remindersListAssetRecord]
          )
          .notify()
        }

        try await userDatabase.read { db in
          let remindersListAsset = try #require(
            try RemindersListAsset.find(1).fetchOne(db)
          )
          #expect(remindersListAsset.coverImage == Data("new-image".utf8))
        }
      }

      // * Receive record with CKAsset from CloudKit when local asset does not exist
      // * Receive updated asset from CloudKit
      // => Local database has freshest asset
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func receiveAssetThenReceiveUpdate() async throws {
        do {
          let remindersListRecord = CKRecord(
            recordType: RemindersList.tableName,
            recordID: RemindersList.recordID(for: 1)
          )
          remindersListRecord.setValue("1", forKey: "id", at: now)
          remindersListRecord.setValue("Personal", forKey: "title", at: now)

          let fileURL = URL(fileURLWithPath: UUID().uuidString)
          try inMemoryDataManager.save(Data("image".utf8), to: fileURL)
          let remindersListAssetRecord = CKRecord(
            recordType: RemindersListAsset.tableName,
            recordID: RemindersListAsset.recordID(for: 1)
          )
          remindersListAssetRecord.setValue("1", forKey: "id", at: now)
          remindersListAssetRecord.setAsset(
            CKAsset(fileURL: fileURL),
            forKey: "coverImage",
            at: now
          )
          remindersListAssetRecord.setValue("1", forKey: "remindersListID", at: now)
          remindersListAssetRecord.parent = CKRecord.Reference(
            record: remindersListRecord,
            action: .none
          )

          try await syncEngine.modifyRecords(
            scope: .private,
            saving: [remindersListAssetRecord, remindersListRecord]
          )
          .notify()
        }

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          let fileURL = URL(fileURLWithPath: UUID().uuidString)
          try inMemoryDataManager.save(Data("new-image".utf8), to: fileURL)
          let remindersListAssetRecord = try syncEngine.private.database.record(
            for: RemindersListAsset.recordID(for: 1)
          )
          remindersListAssetRecord.setAsset(
            CKAsset(fileURL: fileURL),
            forKey: "coverImage",
            at: now
          )
          try await syncEngine.modifyRecords(
            scope: .private,
            saving: [remindersListAssetRecord]
          )
          .notify()
        }

        try await userDatabase.read { db in
          let remindersListAsset = try #require(
            try RemindersListAsset.find(1).fetchOne(db)
          )
          #expect(remindersListAsset.coverImage == Data("new-image".utf8))
        }
      }

      // * Client receives RemindersListAsset with image data
      // * A moment later client receives the parent RemindersList
      // => Both records (and the image data) should be synchronized
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func assetReceivedBeforeParentRecord() async throws {
        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1)
        )
        remindersListRecord.setValue("1", forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)

        let remindersListAssetRecord = CKRecord(
          recordType: RemindersListAsset.tableName,
          recordID: RemindersListAsset.recordID(for: 1)
        )
        remindersListAssetRecord.setValue("1", forKey: "id", at: now)
        remindersListAssetRecord.setBytes(
          Array("image".utf8),
          forKey: "coverImage",
          at: now
        )
        remindersListAssetRecord.setValue(
          "1",
          forKey: "remindersListID",
          at: now
        )
        remindersListAssetRecord.parent = CKRecord.Reference(
          record: remindersListRecord,
          action: .none
        )

        let remindersListModification = try syncEngine.modifyRecords(
          scope: .private,
          saving: [remindersListRecord]
        )
        try await syncEngine.modifyRecords(scope: .private, saving: [remindersListAssetRecord])
          .notify()
        await remindersListModification.notify()

        assertQuery(RemindersList.all, database: userDatabase.database) {
          """
          ┌─────────────────────┐
          │ RemindersList(      │
          │   id: 1,            │
          │   title: "Personal" │
          │ )                   │
          └─────────────────────┘
          """
        }
        assertQuery(RemindersListAsset.all, database: userDatabase.database) {
          """
          ┌─────────────────────────────┐
          │ RemindersListAsset(         │
          │   remindersListID: 1,       │
          │   coverImage: Data(5 bytes) │
          │ )                           │
          └─────────────────────────────┘
          """
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func assetReceivedBeforeParentRecord_RecordNotCached() async throws {
        let remindersListRecord = CKRecord(
          recordType: RemindersList.tableName,
          recordID: RemindersList.recordID(for: 1)
        )
        remindersListRecord.setValue(1, forKey: "id", at: now)
        remindersListRecord.setValue("Personal", forKey: "title", at: now)

        let remindersListAssetRecord = CKRecord(
          recordType: RemindersListAsset.tableName,
          recordID: RemindersListAsset.recordID(for: 1)
        )
        remindersListAssetRecord.setValue(1, forKey: "id", at: now)
        remindersListAssetRecord.setBytes(
          Array("image".utf8),
          forKey: "coverImage",
          at: now
        )
        remindersListAssetRecord.setValue(
          1,
          forKey: "remindersListID",
          at: now
        )
        remindersListAssetRecord.parent = CKRecord.Reference(
          record: remindersListRecord,
          action: .none
        )

        let remindersListModification = try syncEngine.modifyRecords(
          scope: .private,
          saving: [remindersListRecord]
        )
        try await syncEngine.modifyRecords(scope: .private, saving: [remindersListAssetRecord])
          .notify()

        assertQuery(
          UnsyncedRecordID.select { ($0.recordName, $0.record) },
          database: syncEngine.metadatabase
        ) {
          """
          ┌─────────────────────────┬───────────────────────────────────────────────────────────────────────────────────────┐
          │ "1:remindersListAssets" │ CKRecord(                                                                             │
          │                         │   recordID: CKRecord.ID(1:remindersListAssets/zone/__defaultOwner__),                 │
          │                         │   recordType: "remindersListAssets",                                                  │
          │                         │   parent: CKReference(recordID: CKRecord.ID(1:remindersLists/zone/__defaultOwner__)), │
          │                         │   share: nil,                                                                         │
          │                         │   coverImage_hash: Data(32 bytes),                                                    │
          │                         │   id: 1,                                                                              │
          │                         │   remindersListID: 1,                                                                 │
          │                         │   coverImage: CKAsset(                                                                │
          │                         │     fileURL: URL(file:///tmp/00000000-0000-0000-0000-000000000000),                   │
          │                         │     dataString: "image"                                                               │
          │                         │   )                                                                                   │
          │                         │ )                                                                                     │
          └─────────────────────────┴───────────────────────────────────────────────────────────────────────────────────────┘
          """
        }

        await expectDifference(syncEngine.private.database.state.fetchedRecordIDs) {
          await remindersListModification.notify()
        } changes: {
          $0.append(
            RemindersList.recordID(for: 1)
          )
        }
        assertQuery(RemindersListAsset.all, database: userDatabase.database) {
          """
          ┌─────────────────────────────┐
          │ RemindersListAsset(         │
          │   remindersListID: 1,       │
          │   coverImage: Data(5 bytes) │
          │ )                           │
          └─────────────────────────────┘
          """
        }
        assertQuery(UnsyncedRecordID.all, database: syncEngine.metadatabase) {
          """
          (No results)
          """
        }
      }
      
      // * Delete asset row, then insert a new asset row with the same primary key before sending
      // => New asset is saved to CloudKit
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test(.bug("https://github.com/pointfreeco/sqlite-data/issues/418"))
      func deleteThenReinsertAsset() async throws {
        try await seedRemindersListWithAsset()

        try await userDatabase.userWrite { db in
          try RemindersListAsset.find(1).delete().execute(db)
        }
        try await userDatabase.userWrite { db in
          try RemindersListAsset.insert {
            RemindersListAsset(remindersListID: 1, coverImage: Data("new-image".utf8))
          }
          .execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        #expect(try cloudKitCoverImage(remindersListID: 1) == Data("new-image".utf8))
      }

      // * Delete and reinsert asset row in a single transaction before sending
      // => New asset is saved to CloudKit
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test(.bug("https://github.com/pointfreeco/sqlite-data/issues/418"))
      func deleteThenReinsertAsset_SameTransaction() async throws {
        try await seedRemindersListWithAsset()

        try await userDatabase.userWrite { db in
          try RemindersListAsset.find(1).delete().execute(db)
          try RemindersListAsset.insert {
            RemindersListAsset(remindersListID: 1, coverImage: Data("new-image".utf8))
          }
          .execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        #expect(try cloudKitCoverImage(remindersListID: 1) == Data("new-image".utf8))
      }

      // * Delete reminders list (cascading to its asset), then reinsert both before sending
      // => List and new asset are saved to CloudKit
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test(.bug("https://github.com/pointfreeco/sqlite-data/issues/418"))
      func deleteThenReinsertParentAndAsset() async throws {
        try await seedRemindersListWithAsset()

        try await userDatabase.userWrite { db in
          try RemindersList.find(1).delete().execute(db)
        }
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersListAsset(remindersListID: 1, coverImage: Data("new-image".utf8))
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        #expect(
          try container.privateCloudDatabase.record(for: RemindersList.recordID(for: 1))
            .encryptedValues["title"] as? String == "Personal"
        )
        #expect(try cloudKitCoverImage(remindersListID: 1) == Data("new-image".utf8))
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      private func seedRemindersListWithAsset() async throws {
        try await userDatabase.userWrite { db in
          try db.seed {
            RemindersList(id: 1, title: "Personal")
            RemindersListAsset(remindersListID: 1, coverImage: Data("image".utf8))
          }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        #expect(try cloudKitCoverImage(remindersListID: 1) == Data("image".utf8))
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      private func cloudKitCoverImage(remindersListID: Int) throws -> Data? {
        let record = try container.privateCloudDatabase.record(
          for: RemindersListAsset.recordID(for: remindersListID)
        )
        guard let asset = record["coverImage"] as? CKAsset, let fileURL = asset.fileURL
        else { return nil }
        return inMemoryDataManager.storage.withValue { $0[fileURL] }
      }
    }
  }
#endif
