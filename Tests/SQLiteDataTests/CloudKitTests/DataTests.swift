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
    final class DataTests: BaseCloudKitTests, @unchecked Sendable {
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
                  coverImage: [
                    [0]: 105,
                    [1]: 109,
                    [2]: 97,
                    [3]: 103,
                    [4]: 101
                  ],
                  remindersListID: 1
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
                  coverImage: [
                    [0]: 110,
                    [1]: 101,
                    [2]: 119,
                    [3]: 45,
                    [4]: 105,
                    [5]: 109,
                    [6]: 97,
                    [7]: 103,
                    [8]: 101
                  ],
                  remindersListID: 1
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
      }

      // * Receive record with CKAsset from CloudKit
      // => Stored in database as bytes
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test(.disabled()) func receiveData() async throws {
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
        remindersListAssetRecord.setValue(Data("image".utf8), forKey: "coverImage", at: now)
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

      // * Receive record with Data from CloudKit when local asset exists
      // => Stored in database as bytes
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test(.disabled()) func receiveUpdatedData() async throws {
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
          let remindersListAssetRecord = try syncEngine.private.database.record(
            for: RemindersListAsset.recordID(for: 1)
          )
          remindersListAssetRecord.setValue(
            Data("new-image".utf8),
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
      @Test(.disabled()) func receiveAssetThenReceiveUpdate() async throws {
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
      @Test(.disabled()) func assetReceivedBeforeParentRecord() async throws {
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
