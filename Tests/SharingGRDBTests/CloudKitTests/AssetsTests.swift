import CloudKit
import ConcurrencyExtras
import CustomDump
import InlineSnapshotTesting
import OrderedCollections
import SharingGRDB
import SnapshotTestingCustomDump
import Testing

extension BaseCloudKitTests {
  @MainActor
  final class AssetsTests: BaseCloudKitTests, @unchecked Sendable {
    @Dependency(\.date.now) var now
    @Dependency(\.dataManager) var dataManager
    var inMemoryDataManager: InMemoryDataManager {
      dataManager as! InMemoryDataManager
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func basics() async throws {
      try await userDatabase.userWrite { db in
        try db.seed {
          RemindersList(id: UUID(1), title: "Personal")
          RemindersListAsset(id: UUID(1), coverImage: Data("image".utf8), remindersListID: UUID(1))
        }
      }

      await syncEngine.processBatch()

      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersListAssets/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersListAssets",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                remindersListID: "00000000-0000-0000-0000-000000000001",
                coverImage: CKAsset(
                  fileURL: URL(file:///6105d6cc76af400325e94d588ce511be5bfdbb73b437dc51eca43917d7a43e3d),
                  dataString: "image"
                )
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
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
        let url = URL(string: "file:///6105d6cc76af400325e94d588ce511be5bfdbb73b437dc51eca43917d7a43e3d")!
        #expect(storage[url] == Data("image".utf8))
      }

      try await withDependencies {
        $0.date.now.addTimeInterval(1)
      } operation: {
        try await userDatabase.userWrite { db in
          try RemindersListAsset
            .find(UUID(1))
            .update { $0.coverImage = Data("new-image".utf8) }
            .execute(db)
        }
      }

      await syncEngine.processBatch()

      assertInlineSnapshot(of: syncEngine.container, as: .customDump) {
        """
        MockCloudContainer(
          privateCloudDatabase: MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:remindersListAssets/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersListAssets",
                parent: CKReference(recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__)),
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
                remindersListID: "00000000-0000-0000-0000-000000000001",
                coverImage: CKAsset(
                  fileURL: URL(file:///97e67a5645969953f1a4cfe2ea75649864ff99789189cdd3f6db03e59f8a8ebf),
                  dataString: "new-image"
                )
              ),
              [1]: CKRecord(
                recordID: CKRecord.ID(1:remindersLists/co.pointfree.SQLiteData.defaultZone/__defaultOwner__),
                recordType: "remindersLists",
                parent: nil,
                share: nil,
                id: "00000000-0000-0000-0000-000000000001",
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
        let url = URL(string: "file:///97e67a5645969953f1a4cfe2ea75649864ff99789189cdd3f6db03e59f8a8ebf")!
        #expect(storage[url] == Data("new-image".utf8))
      }
    }


    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func receiveAsset() async throws {
      let remindersListRecord = CKRecord(
        recordType: RemindersList.tableName,
        recordID: RemindersList.recordID(for: UUID(1))
      )
      remindersListRecord.setValue(UUID(1).uuidString.lowercased(), forKey: "id", at: now)
      remindersListRecord.setValue("Personal", forKey: "title", at: now)

      let remindersListAssetRecord = CKRecord(
        recordType: RemindersListAsset.tableName,
        recordID: RemindersListAsset.recordID(for: UUID(1))
      )
      remindersListAssetRecord.setValue(UUID(1).uuidString.lowercased(), forKey: "id", at: now)
      remindersListAssetRecord.setValue(
        Array("image".utf8),
        forKey: "coverImage",
        at: now
      )
      remindersListAssetRecord.setValue(
        UUID(1).uuidString.lowercased(),
        forKey: "remindersListID",
        at: now
      )
      remindersListAssetRecord.parent = CKRecord.Reference(
        record: remindersListRecord,
        action: .none
      )

      await syncEngine.modifyRecords(
        scope: .private,
        saving: [remindersListRecord, remindersListAssetRecord]
      )

      try {
        try userDatabase.read { db in
          let remindersListAsset = try #require(try RemindersListAsset.find(UUID(1)).fetchOne(db))
          #expect(remindersListAsset.coverImage == Data("image".utf8))
        }
      }()
    }
  }
}
