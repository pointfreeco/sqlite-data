import Dependencies
import DependenciesTestSupport
import Sharing
import SharingGRDB
import StructuredQueries
import Testing

@Suite(.dependency(\.defaultDatabase, try .syncUps()))
struct IntegrationTests {
  @Dependency(\.defaultDatabase) var database

  @Test
  func fetchAll_SQLString() async throws {
    @FetchAll(SyncUp.where(\.isActive)) var syncUps: [SyncUp]
    #expect(syncUps == [])

    try await database.write { db in
      _ = try SyncUp.insert { SyncUp.Draft(isActive: true, title: "Engineering") }
        .execute(db)
    }
    try await $syncUps.load()
    #expect(syncUps == [SyncUp(id: 1, isActive: true, title: "Engineering")])
    try await database.write { db in
      _ = try SyncUp.upsert { SyncUp.Draft(id: 1, isActive: false, title: "Engineering") }
        .execute(db)
    }
    try await $syncUps.load()
    #expect(syncUps == [])
    try await database.write { db in
      _ = try SyncUp.upsert { SyncUp.Draft(id: 1, isActive: true, title: "Engineering") }
        .execute(db)
    }
    try await $syncUps.load()
    #expect(syncUps == [SyncUp(id: 1, isActive: true, title: "Engineering")])
  }

  @Test
  func fetch_FetchKeyRequest() async throws {
    @Fetch(ActiveSyncUps()) var syncUps: [SyncUp] = []
    #expect(syncUps == [])

    try await database.write { db in
      _ = try SyncUp.insert { SyncUp.Draft(isActive: true, title: "Engineering") }
        .execute(db)
    }
    try await $syncUps.load()
    #expect(syncUps == [SyncUp(id: 1, isActive: true, title: "Engineering")])
    try await database.write { db in
      _ = try SyncUp.upsert { SyncUp.Draft(id: 1, isActive: false, title: "Engineering") }
        .execute(db)
    }
    try await $syncUps.load()
    #expect(syncUps == [])
    try await database.write { db in
      _ = try SyncUp.upsert { SyncUp.Draft(id: 1, isActive: true, title: "Engineering") }
        .execute(db)
    }
    try await $syncUps.load()
    #expect(syncUps == [SyncUp(id: 1, isActive: true, title: "Engineering")])
  }
}

@Table
private struct SyncUp: Equatable, Identifiable {
  let id: Int
  var isActive: Bool
  var title: String
}

@Table
private struct Attendee: Equatable {
  let id: Int
  var name: String
  var syncUpID: SyncUp.ID
}

extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func syncUps() throws -> Self {
    let database = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create schema") { db in
      try #sql(
        """
        CREATE TABLE "syncUps" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "isActive" INTEGER NOT NULL,
          "title" TEXT NOT NULL
        )
        """
      )
      .execute(db)
      try #sql(
        """
        CREATE TABLE "attendees" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "syncUpID" INTEGER NOT NULL,
          "name" TEXT NOT NULL,

          FOREIGN KEY("syncUpID") REFERENCES "syncUps"("id")
        )
        """
      )
      .execute(db)
    }
    try migrator.migrate(database)
    return database
  }
}

private struct ActiveSyncUps: FetchKeyRequest {
  func fetch(_ db: Database) throws -> [SyncUp] {
    try SyncUp
      .where(\.isActive)
      .fetchAll(db)
  }
}
