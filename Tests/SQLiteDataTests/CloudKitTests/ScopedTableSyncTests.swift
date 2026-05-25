#if canImport(CloudKit)
  import CloudKit
  import CustomDump
  import Foundation
  import InlineSnapshotTesting
  import SQLiteData
  import SQLiteDataTestSupport
  import SnapshotTestingCustomDump
  import Testing

  // Scoped-out rows must remain reachable by every SyncEngine primary-key path.
  @MainActor
  @Suite
  struct ScopedTableSyncTests {
    struct Fixture {
      let userDatabase: UserDatabase
      let syncEngine: SyncEngine
      let container: MockCloudContainer
      let zoneID: CKRecordZone.ID
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    static func makeFixture() async throws -> Fixture {
      let containerIdentifier = "iCloud.co.pointfree.Testing.\(UUID())"
      let database = try DatabasePool(
        path: URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite").path()
      )
      try await database.write { db in
        try #sql(
          """
          CREATE TABLE "scopedModels" (
            "id" INT PRIMARY KEY NOT NULL,
            "title" TEXT NOT NULL ON CONFLICT REPLACE DEFAULT '',
            "isDeleted" INTEGER NOT NULL ON CONFLICT REPLACE DEFAULT 0
          ) STRICT
          """
        )
        .execute(db)
      }
      let userDatabase = UserDatabase(database: database)
      let privateDatabase = MockCloudDatabase(databaseScope: .private)
      let sharedDatabase = MockCloudDatabase(databaseScope: .shared)
      let container = MockCloudContainer(
        containerIdentifier: containerIdentifier,
        privateCloudDatabase: privateDatabase,
        sharedCloudDatabase: sharedDatabase
      )
      privateDatabase.set(container: container)
      sharedDatabase.set(container: container)
      let syncEngine = try await SyncEngine(
        container: container,
        userDatabase: userDatabase,
        tables: [SynchronizedTable(for: ScopedModel.self)]
      )
      let currentUser = CKRecord.ID(recordName: "currentUser")
      await syncEngine.handleEvent(
        .accountChange(changeType: .signIn(currentUser: currentUser)),
        syncEngine: syncEngine.private
      )
      await syncEngine.handleEvent(
        .accountChange(changeType: .signIn(currentUser: currentUser)),
        syncEngine: syncEngine.shared
      )
      try await syncEngine.processPendingDatabaseChanges(scope: .private)
      return Fixture(
        userDatabase: userDatabase,
        syncEngine: syncEngine,
        container: container,
        zoneID: syncEngine.defaultZone.zoneID
      )
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func outgoingSaveLookupIncludesScopedOutRow() async throws {
      let fx = try await Self.makeFixture()
      try await fx.userDatabase.userWrite { db in
        try db.seed { ScopedModel(id: 1, title: "Important", isDeleted: false) }
      }
      try await fx.syncEngine.processPendingRecordZoneChanges(scope: .private)
      try await fx.userDatabase.userWrite { db in
        try ScopedModel.unscoped.find(1).update { $0.isDeleted = true }.execute(db)
      }
      try await fx.syncEngine.processPendingRecordZoneChanges(scope: .private)
      assertInlineSnapshot(of: fx.container.privateCloudDatabase, as: .customDump) {
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
      let fx = try await Self.makeFixture()
      try await fx.userDatabase.userWrite { db in
        try db.seed { ScopedModel(id: 1, title: "x", isDeleted: false) }
      }
      try await fx.syncEngine.processPendingRecordZoneChanges(scope: .private)
      try await fx.userDatabase.userWrite { db in
        try ScopedModel.unscoped.find(1).update { $0.isDeleted = true }.execute(db)
      }

      try await fx.syncEngine.modifyRecordZones(
        scope: .private,
        deleting: [fx.zoneID]
      ).notify()
      try await fx.syncEngine.processPendingDatabaseChanges(scope: .private)

      try await fx.userDatabase.read { db in
        try #expect(ScopedModel.unscoped.fetchAll(db) == [])
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func encryptedDataResetReuploadsScopedOutRow() async throws {
      let fx = try await Self.makeFixture()
      try await fx.userDatabase.userWrite { db in
        try db.seed { ScopedModel(id: 1, title: "x", isDeleted: false) }
      }
      try await fx.syncEngine.processPendingRecordZoneChanges(scope: .private)
      try await fx.userDatabase.userWrite { db in
        try ScopedModel.unscoped.find(1).update { $0.isDeleted = true }.execute(db)
      }
      try await fx.syncEngine.processPendingRecordZoneChanges(scope: .private)

      await fx.syncEngine.handleEvent(
        SyncEngine.Event.fetchedDatabaseChanges(
          modifications: [],
          deletions: [(fx.zoneID, .encryptedDataReset)]
        ),
        syncEngine: fx.syncEngine.private
      )
      try await fx.syncEngine.processPendingRecordZoneChanges(scope: .private)

      try await fx.userDatabase.read { db in
        try #expect(ScopedModel.unscoped.fetchAll(db).count == 1)
      }
      assertInlineSnapshot(of: fx.container.privateCloudDatabase, as: .customDump) {
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
              title: "x"
            )
          ]
        )
        """
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func serverDeleteRemovesScopedOutRow() async throws {
      let fx = try await Self.makeFixture()
      try await fx.userDatabase.userWrite { db in
        try db.seed { ScopedModel(id: 1, title: "x", isDeleted: false) }
      }
      try await fx.syncEngine.processPendingRecordZoneChanges(scope: .private)
      try await fx.userDatabase.userWrite { db in
        try ScopedModel.unscoped.find(1).update { $0.isDeleted = true }.execute(db)
      }

      try await fx.syncEngine.modifyRecords(
        scope: .private,
        deleting: [ScopedModel.recordID(for: 1)]
      ).notify()
      try await fx.syncEngine.processPendingRecordZoneChanges(scope: .private)

      try await fx.userDatabase.read { db in
        try #expect(ScopedModel.unscoped.fetchAll(db) == [])
      }
    }

    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    @Test func serverModificationMergesScopedOutRow() async throws {
      let fx = try await Self.makeFixture()
      try await fx.userDatabase.userWrite { db in
        try db.seed { ScopedModel(id: 1, title: "x", isDeleted: false) }
      }
      try await fx.syncEngine.processPendingRecordZoneChanges(scope: .private)
      try await fx.userDatabase.userWrite { db in
        try ScopedModel.unscoped.find(1).update { $0.isDeleted = true }.execute(db)
      }
      try await fx.syncEngine.processPendingRecordZoneChanges(scope: .private)

      let serverRecord = CKRecord(
        recordType: ScopedModel.tableName,
        recordID: ScopedModel.recordID(for: 1)
      )
      serverRecord["id"] = 1
      serverRecord["title"] = "from-server"
      serverRecord["isDeleted"] = 1
      await fx.syncEngine.handleEvent(
        SyncEngine.Event.fetchedRecordZoneChanges(
          modifications: [serverRecord],
          deletions: []
        ),
        syncEngine: fx.syncEngine.private
      )

      try await fx.userDatabase.read { db in
        let rows = try ScopedModel.unscoped.fetchAll(db)
        #expect(rows.count == 1)
        #expect(rows.first?.isDeleted == true)
      }
    }
  }
#endif
