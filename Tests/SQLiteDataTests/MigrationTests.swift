import Foundation
import SQLiteData
import Testing

@Suite struct MigrationTests {
  @available(iOS 15, *)
  @Test func dates() throws {
    let database = try DatabaseQueue()
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "models" (
          "date" TEXT NOT NULL
        )
        """
      )
      .execute(db)
    }

    let timestamp = 123.456
    try database.write { db in
      try db.execute(
        literal: "INSERT INTO models (date) VALUES (\(Date(timeIntervalSince1970: timestamp)))"
      )
    }
    try database.read { db in
      let grdbDate = try Date.fetchOne(db, sql: "SELECT * FROM models")
      try #expect(abs(#require(grdbDate).timeIntervalSince1970 - timestamp) < 0.001)

      let date = try #require(try Model.all.fetchOne(db)).date
      #expect(abs(date.timeIntervalSince1970 - timestamp) < 0.001)
    }
  }
}


@available(iOS 15, *)
@Table private struct Model {
  var date: Date
}


#if canImport(CloudKit)
  @available(iOS 15, *)
  @Table private struct User: Identifiable {
    var id: UUID
    var name: String
  }

  @Table("users") private struct UpdatedUser: Identifiable {
    var id: UUID
    var name: String
    var honorific: String?
  }

  import CloudKit
  import ConcurrencyExtras
  import CustomDump
  import InlineSnapshotTesting
  import OrderedCollections
  import SQLiteData
  import SQLiteDataTestSupport
  import SnapshotTestingCustomDump
  import Testing

  @MainActor
  @Suite
  final class MigrationSyncEngineTests {
    @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
    
    private let _container: any Sendable

    var container: MockCloudContainer {
      _container as! MockCloudContainer
    }
    
    let testContainerIdentifier: String
    let databaseURL: URL
    
    func userDatabase() throws -> UserDatabase {
      UserDatabase(
        database: try SQLiteDataTests.database(
          containerIdentifier: testContainerIdentifier,
          attachMetadatabase: false,
          url: databaseURL
        )
      )
    }

    
    init() async throws {
      testContainerIdentifier = "iCloud.co.pointfree.Testing.\(UUID())"
      databaseURL = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).sqlite")
      
      let privateDatabase = MockCloudDatabase(databaseScope: .private)
      let sharedDatabase = MockCloudDatabase(databaseScope: .shared)
      let container = MockCloudContainer(
        accountStatus: _AccountStatusScope.accountStatus,
        containerIdentifier: testContainerIdentifier,
        privateCloudDatabase: privateDatabase,
        sharedCloudDatabase: sharedDatabase
      )
      _container = container
      privateDatabase.set(container: container)
      sharedDatabase.set(container: container)
    }
    
    @available(iOS 15, *)
    @Test func handleDataMigration() async throws {
      let userDatabase = try userDatabase()
      // Do first migration
      try await userDatabase.userWrite { db in
        try #sql(
          """
          CREATE TABLE "users" (
            "id" TEXT PRIMARY KEY NOT NULL ON CONFLICT REPLACE DEFAULT (uuid()),
            "name" TEXT NOT NULL
          )
          """
        )
        .execute(db)
      }
      
      var syncEngine: Optional<SyncEngine> = try await SyncEngine(
        container: container,
        userDatabase: userDatabase,
        delegate: nil,
        privateTables: User.self,
        startImmediately: true
      )
      
      let currentUserRecordID = CKRecord.ID(
        recordName: "currentUser"
      )
      
      await syncEngine!.handleEvent(
        .accountChange(changeType: .signIn(currentUser: currentUserRecordID)),
        syncEngine: syncEngine!.private
      )
      await syncEngine!.handleEvent(
        .accountChange(changeType: .signIn(currentUser: currentUserRecordID)),
        syncEngine: syncEngine!.shared
      )
      try await syncEngine!.processPendingDatabaseChanges(scope: .private)
      
      try await userDatabase.userWrite { db in
        try User.insert {
          User.Draft(name: "Bob")
          User.Draft(name: "Alice")
          User.Draft(name: "Alfred")
        }.execute(db)
      }
      
      // Do we need to await something here?
      try await Task.sleep(for: .seconds(1))
      try await syncEngine?.processPendingRecordZoneChanges(scope: .private)
      syncEngine?.stop()
      syncEngine = nil
      
      try userDatabase.database.close()
      
      let newDbConnection = try self.userDatabase()
      
      try await newDbConnection.userWrite { db in
        try #sql(
          """
          ALTER TABLE "users"
          ADD COLUMN "honorific" TEXT
          """
        )
        .execute(db)
        
        let existingUsers = try UpdatedUser.all.fetchAll(db)
        for user in existingUsers {
          switch user.name.lowercased() {
          case "bob":
            try UpdatedUser.find(user.id).update {
              $0.honorific = "Mr"
            }.execute(db)
          case "alice":
            try UpdatedUser.find(user.id).update {
              $0.honorific = "Ms"
            }.execute(db)
          default:
            continue
          }
        }
      }
      
      syncEngine = try await SyncEngine(
        container: container,
        userDatabase: newDbConnection,
        delegate: nil,
        privateTables: UpdatedUser.self,
        startImmediately: true
      )
      
      let bob = try await newDbConnection.read { db in
        try UpdatedUser.all.where { $0.name.eq("Bob") }.fetchOne(db)
      }
      #expect(bob?.honorific == "Mr")
    }
    
   
    
    // Do we need to wait here...
  }
#endif
