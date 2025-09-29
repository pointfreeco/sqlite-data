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
      @Dependency(\.dataManager) var dataManager
      var inMemoryDataManager: InMemoryDataManager {
        dataManager as! InMemoryDataManager
      }

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
                    fileURL: URL(file:///6105d6cc76af400325e94d588ce511be5bfdbb73b437dc51eca43917d7a43e3d),
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
            string: "file:///6105d6cc76af400325e94d588ce511be5bfdbb73b437dc51eca43917d7a43e3d"
          )!
          #expect(storage[url] == Data("image".utf8))
        }

        try await withDependencies {
          $0.currentTime.now += 1
        } operation: {
          try await userDatabase.userWrite { db in
            try RemindersListAsset
              .find(1)
              .update { $0.coverImage = Data("new-image".utf8) }
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
                    fileURL: URL(file:///97e67a5645969953f1a4cfe2ea75649864ff99789189cdd3f6db03e59f8a8ebf),
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
            string: "file:///97e67a5645969953f1a4cfe2ea75649864ff99789189cdd3f6db03e59f8a8ebf"
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
        remindersListAssetRecord.setValue(
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
    }
  }
#endif
