#if canImport(CloudKit)
  import Clocks
  import CloudKit
  import Dependencies
  import DependenciesTestSupport
  import GRDB
  import SQLiteData
  import Testing

  @MainActor
  @Suite(
    .dependencies {
      $0.currentTime.now = 0
      $0.continuousClock = TestClock<Duration>()
      $0.cloudKitClock = TestClock<Duration>()
      $0.dataManager = InMemoryDataManager()
    }
  )
  struct JSONBTests {
    let userDatabase: UserDatabase
    private let _syncEngine: any Sendable
    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
    var syncEngine: SyncEngine { _syncEngine as! SyncEngine }
    @Dependency(\.dataManager) var dataManager

    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
    init() async throws {
      let database = try DatabasePool(
        path: URL.temporaryDirectory.appending(path: "\(UUID()).sqlite").path()
      )
      try await database.write { db in
        try db.execute(
          sql: """
            CREATE TABLE "jsonbDocuments" (
              "id" INTEGER PRIMARY KEY NOT NULL,
              "value" BLOB NOT NULL,
              "optionalValue" BLOB,
              "textValue" TEXT NOT NULL,
              "data" BLOB NOT NULL
            ) STRICT
            """
        )
      }
      userDatabase = UserDatabase(database: database)
      let container = MockCloudContainer.createContainer(
        identifier: "iCloud.co.pointfree.Testing.\(UUID())"
      )
      _syncEngine = try await SyncEngine(
        container: container,
        userDatabase: userDatabase,
        tables: [SynchronizedTable(for: JSONBDocument.self)]
      )
      await syncEngine.handleEvent(
        .accountChange(changeType: .signIn(currentUser: CKRecord.ID(recordName: "currentUser"))),
        syncEngine: syncEngine.private
      )
      try await syncEngine.processPendingDatabaseChanges(scope: .private)
    }

    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
    @Test func roundTrip() async throws {
      let document = JSONBDocument(
        id: 1,
        value: ["original"],
        optionalValue: ["optional"],
        textValue: ["text"],
        data: Data("asset".utf8)
      )
      try await userDatabase.userWrite { db in
        try JSONBDocument.insert { document }.execute(db)
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      let record = try syncEngine.private.database.record(for: JSONBDocument.recordID(for: 1))
      let asset = try #require(record["value"] as? CKAsset)
      let bytes = try dataManager.load(#require(asset.fileURL))
      #expect(record.encryptedValues["value"] == nil)
      #expect(record["optionalValue"] is CKAsset)
      let text = try #require(record.encryptedValues["textValue"] as? String)
      let textValue = try JSONDecoder().decode([String].self, from: Data(text.utf8))
      #expect(textValue == ["text"])
      #expect(record["data"] is CKAsset)
      try await userDatabase.read { db in
        try #expect(
          String.fetchOne(db, sql: "SELECT json(?)", arguments: [bytes]) == "[\"original\"]")
      }

      let receiver = try await JSONBTests()
      await receiver.syncEngine.handleEvent(
        .fetchedRecordZoneChanges(modifications: [record], deletions: []),
        syncEngine: receiver.syncEngine.private
      )
      try await receiver.userDatabase.read { db in
        try #expect(JSONBDocument.find(1).fetchOne(db) == document)
        try #expect(String.fetchOne(db, sql: "SELECT typeof(value) FROM jsonbDocuments") == "blob")
      }

      let updatedBytes = try await userDatabase.read { db in
        try #require(try Data.fetchOne(db, sql: "SELECT jsonb('[\"updated\"]')"))
      }
      let updatedRecord = record.copy() as! CKRecord
      updatedRecord.setBytes(Array(updatedBytes), forKey: "value", at: 1)
      updatedRecord.removeValue(forKey: "optionalValue", at: 1)
      await receiver.syncEngine.handleEvent(
        .fetchedRecordZoneChanges(modifications: [updatedRecord], deletions: []),
        syncEngine: receiver.syncEngine.private
      )
      try await receiver.userDatabase.read { db in
        let updated = try #require(try JSONBDocument.find(1).fetchOne(db))
        #expect(updated.value == ["updated"])
        #expect(updated.optionalValue == nil)
        try #expect(String.fetchOne(db, sql: "SELECT typeof(value) FROM jsonbDocuments") == "blob")
        try #expect(
          String.fetchOne(db, sql: "SELECT json(value) FROM jsonbDocuments") == "[\"updated\"]")
      }
    }

    @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
    @Test func merge() async throws {
      try await userDatabase.userWrite { db in
        try JSONBDocument.insert {
          JSONBDocument(
            id: 1, value: ["original"], optionalValue: nil, textValue: [], data: Data()
          )
        }.execute(db)
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      let record = try syncEngine.private.database.record(for: JSONBDocument.recordID(for: 1))
      let remoteBytes = try await userDatabase.read { db in
        try #require(try Data.fetchOne(db, sql: "SELECT jsonb('[\"remote\"]')"))
      }
      record.setBytes(Array(remoteBytes), forKey: "value", at: 1)
      try await withDependencies {
        $0.currentTime.now = 2
      } operation: {
        try await userDatabase.userWrite { db in
          try JSONBDocument.find(1).update { $0.textValue = #bind(["local"]) }.execute(db)
        }
      }
      await syncEngine.handleEvent(
        .fetchedRecordZoneChanges(modifications: [record], deletions: []),
        syncEngine: syncEngine.private
      )
      try await userDatabase.read { db in
        let document = try #require(try JSONBDocument.find(1).fetchOne(db))
        #expect(document.value == ["remote"])
        #expect(document.textValue == ["local"])
      }

      try await withDependencies {
        $0.currentTime.now = 3
      } operation: {
        try await userDatabase.userWrite { db in
          try JSONBDocument.find(1).update { $0.value = #bind(["local"]) }.execute(db)
        }
      }
      let olderRecord = record.copy() as! CKRecord
      olderRecord.setBytes(Array(remoteBytes), forKey: "value", at: 2)
      await syncEngine.handleEvent(
        .fetchedRecordZoneChanges(modifications: [olderRecord], deletions: []),
        syncEngine: syncEngine.private
      )
      try await userDatabase.read { db in
        try #expect(JSONBDocument.find(1).fetchOne(db)?.value == ["local"])
      }
      try await syncEngine.processPendingRecordZoneChanges(scope: .private)
      let uploaded = try syncEngine.private.database.record(for: JSONBDocument.recordID(for: 1))
      let asset = try #require(uploaded["value"] as? CKAsset)
      let fileURL = try #require(asset.fileURL)
      #expect(
        uploaded.encryptedValues["value_hash"] as? Data
          == dataManager.sha256(of: fileURL)
      )
      #expect(uploaded.encryptedValues["\(CKRecord.userModificationTimeKey)_value"] as? Int64 == 3)
    }
  }

  @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
  @Table("jsonbDocuments")
  private struct JSONBDocument: Equatable {
    let id: Int
    @Column(as: [String].JSONBRepresentation.self)
    var value: [String]
    @Column(as: [String]?.JSONBRepresentation.self)
    var optionalValue: [String]?
    @Column(as: [String].JSONRepresentation.self)
    var textValue: [String]
    var data: Data
  }
#endif
