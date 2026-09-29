#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import Foundation
  import InlineSnapshotTesting
  import SQLiteData
  import SQLiteDataTestSupport
  import SnapshotTestingCustomDump
  import Testing

  extension BaseCloudKitTests {
    @MainActor
    final class ScopedTableSyncTests: BaseCloudKitTests, @unchecked Sendable {
      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func outgoingSaveLookupIncludesScopedOutRow() async throws {
        try await userDatabase.userWrite { db in
          try db.seed { ScopedModel(id: 1, title: "Important", isDeleted: false) }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        try await userDatabase.userWrite { db in
          try ScopedModel.unscoped.find(1).update { $0.isDeleted = true }.execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        assertInlineSnapshot(of: container.privateCloudDatabase, as: .customDump) {
          """
          MockCloudDatabase(
            databaseScope: .private,
            storage: [
              [0]: CKRecord(
                recordID: CKRecord.ID(1:scopedModels/zone/__defaultOwner__),
                recordType: "scopedModels",
                parent: nil,
                share: nil,
                id: 1,
                isDeleted: 1,
                title: "Important"
              )
            ]
          )
          """
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func zoneDeletionRemovesScopedOutRow() async throws {
        try await userDatabase.userWrite { db in
          try db.seed { ScopedModel(id: 1, title: "x", isDeleted: false) }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        try await userDatabase.userWrite { db in
          try ScopedModel.unscoped.find(1).update { $0.isDeleted = true }.execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await syncEngine.modifyRecordZones(
          scope: .private,
          deleting: [syncEngine.defaultZone.zoneID]
        ).notify()
        try await syncEngine.processPendingDatabaseChanges(scope: .private)

        try await userDatabase.read { db in
          try #expect(ScopedModel.unscoped.fetchAll(db) == [])
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func encryptedDataResetReuploadsScopedOutRow() async throws {
        try await userDatabase.userWrite { db in
          try db.seed { ScopedModel(id: 1, title: "x", isDeleted: false) }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        try await userDatabase.userWrite { db in
          try ScopedModel.unscoped.find(1).update { $0.isDeleted = true }.execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        await syncEngine.handleEvent(
          SyncEngine.Event.fetchedDatabaseChanges(
            modifications: [],
            deletions: [(syncEngine.defaultZone.zoneID, .encryptedDataReset)]
          ),
          syncEngine: syncEngine.private
        )
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.read { db in
          try #expect(ScopedModel.unscoped.fetchAll(db).count == 1)
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func serverDeleteRemovesScopedOutRow() async throws {
        try await userDatabase.userWrite { db in
          try db.seed { ScopedModel(id: 1, title: "x", isDeleted: false) }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        try await userDatabase.userWrite { db in
          try ScopedModel.unscoped.find(1).update { $0.isDeleted = true }.execute(db)
        }

        try await syncEngine.modifyRecords(
          scope: .private,
          deleting: [ScopedModel.recordID(for: 1)]
        ).notify()
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        try await userDatabase.read { db in
          try #expect(ScopedModel.unscoped.fetchAll(db) == [])
        }
      }

      @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
      @Test func serverModificationMergesScopedOutRow() async throws {
        try await userDatabase.userWrite { db in
          try db.seed { ScopedModel(id: 1, title: "x", isDeleted: false) }
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)
        try await userDatabase.userWrite { db in
          try ScopedModel.unscoped.find(1).update { $0.isDeleted = true }.execute(db)
        }
        try await syncEngine.processPendingRecordZoneChanges(scope: .private)

        let serverRecord = CKRecord(
          recordType: ScopedModel.tableName,
          recordID: ScopedModel.recordID(for: 1)
        )
        serverRecord["id"] = 1
        serverRecord["title"] = "from-server"
        serverRecord["isDeleted"] = 1
        await syncEngine.handleEvent(
          SyncEngine.Event.fetchedRecordZoneChanges(
            modifications: [serverRecord],
            deletions: []
          ),
          syncEngine: syncEngine.private
        )

        try await userDatabase.read { db in
          let rows = try ScopedModel.unscoped.fetchAll(db)
          #expect(rows.count == 1)
          #expect(rows.first?.isDeleted == true)
        }
      }
    }
  }
#endif
