import Dependencies
import DependenciesTestSupport
import GRDB
import Sharing
import SharingGRDB
import Testing

@MainActor @Suite(.dependency(\.defaultDatabase, try .syncUps()))
struct IntegrationTests {
  @Test
  func fetchAll_SQLString() async throws {
    @SharedReader(.fetchAll(sql: #"SELECT * FROM "syncUps" WHERE "isActive""#))
    var syncUps: [SyncUp] = []
    #expect(syncUps == [])

    @Dependency(\.defaultDatabase) var database
    try await database.write { db in
      _ = try SyncUp(isActive: true, title: "Engineering")
        .inserted(db)
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(syncUps == [SyncUp(id: 1, isActive: true, title: "Engineering")])
    try await database.write { db in
      _ = try SyncUp(id: 1, isActive: false, title: "Engineering")
        .saved(db)
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(syncUps == [])
    try await database.write { db in
      _ = try SyncUp(id: 1, isActive: true, title: "Engineering")
        .saved(db)
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(syncUps == [SyncUp(id: 1, isActive: true, title: "Engineering")])
  }

  @Test
  func fetch_FetchKeyRequest() async throws {
    @SharedReader(.fetch(ActiveSyncUps()))
    var syncUps: [SyncUp] = []
    #expect(syncUps == [])

    @Dependency(\.defaultDatabase) var database
    try await database.write { db in
      _ = try SyncUp(isActive: true, title: "Engineering")
        .inserted(db)
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(syncUps == [SyncUp(id: 1, isActive: true, title: "Engineering")])
    try await database.write { db in
      _ = try SyncUp(id: 1, isActive: false, title: "Engineering")
        .saved(db)
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(syncUps == [])
    try await database.write { db in
      _ = try SyncUp(id: 1, isActive: true, title: "Engineering")
        .saved(db)
    }
    try await Task.sleep(nanoseconds: 10_000_000)
    #expect(syncUps == [SyncUp(id: 1, isActive: true, title: "Engineering")])
  }
}

private struct SyncUp: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
  var id: Int64?
  var isActive: Bool
  var title: String
  static let databaseTableName = "syncUps"
  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

private struct Attendee: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
  var id: Int64?
  var name: String
  var syncUpID: Int
  static let databaseTableName = "attendees"
  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

private extension DatabaseWriter where Self == DatabaseQueue {
  static func syncUps() throws -> Self {
    let database = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create schema") { db in
      try db.create(table: SyncUp.databaseTableName) { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("isActive", .boolean).notNull()
        t.column("title", .text).notNull()
      }
      try db.create(table: Attendee.databaseTableName) { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("syncUpID", .integer).notNull()
        t.column("name", .text).notNull()
      }
    }
    try migrator.migrate(database)
    return database
  }
}

private struct ActiveSyncUps: FetchKeyRequest {
  func fetch(_ db: Database) throws -> [SyncUp] {
    try SyncUp
      .all()
      .filter(Column("isActive"))
      .fetchAll(db)
  }
}
