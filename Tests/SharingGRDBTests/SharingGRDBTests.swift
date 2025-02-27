import Dependencies
import GRDB
import Sharing
import SharingGRDB
import Testing

@Suite struct GRDBSharingTests {
  @Test
  func fetchOne() async throws {
    try await withDependencies {
      $0.defaultDatabase = try DatabaseQueue()
    } operation: {
      @SharedReader(.fetchOne(sql: "SELECT 1")) var bool = false
      try await Task.sleep(nanoseconds: 10_000_000)
      #expect(bool)
      #expect($bool.loadError == nil)
    }
  }

  @Test
  func fetchOneOptional() async throws {
    try withDependencies {
      $0.defaultDatabase = try DatabaseQueue()
    } operation: {
      @SharedReader(.fetchOne(sql: "SELECT NULL")) var bool: Bool?
      #expect(bool == nil)
    }
  }

  @Test func fetchSyntaxError() async throws {
    try await withDependencies {
      $0.defaultDatabase = try DatabaseQueue()
    } operation: {
      @SharedReader(.fetchOne(sql: "SELEC 1")) var bool = false
      #expect(bool == false)
      try await Task.sleep(nanoseconds: 10_000_000)
      #expect($bool.loadError is DatabaseError?)
      let error = try #require($bool.loadError as? DatabaseError)
      #expect(error.message == #"near "SELEC": syntax error"#)
    }
  }

  @Test func fetchWithTwoDatabaseConnections() async throws {
    try await withDependencies {
      $0.defaultDatabase = try .database
    } operation: {
      @SharedReader(.fetchAll(sql: "SELECT * FROM records")) var records1: [Record] = []
      try await Task.sleep(nanoseconds: 100_000_000)
      #expect(records1.map(\.id) == [1, 2, 3])

      try await withDependencies {
        $0.defaultDatabase = try .database
      } operation: {
        @Dependency(\.defaultDatabase) var database2
        @SharedReader(.fetchAll(sql: "SELECT * FROM records")) var records2: [Record] = []
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(records2.map(\.id) == [1, 2, 3])
        try await database2.write { db in
          _ = try Record.deleteOne(db, key: 1)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(records1.map(\.id) == [1, 2, 3])
        #expect(records2.map(\.id) == [2, 3])
      }

      try await $records1.load()
      #expect(records1.map(\.id) == [2, 3])
    }
  }

  @Test(.dependency(\.defaultDatabase, try .database))
  func fetchIDHashValue() async throws {
    let fetchKey1: some SharedReaderKey<Void> = .fetch(Fetch1())
    let fetchKey2: some SharedReaderKey<Void> = .fetch(Fetch2())
    #expect(fetchKey1.id.hashValue != fetchKey2.id.hashValue)
  }

  @Test(.dependency(\.defaultDatabase, try .database))
  func fetchAnimationHashValue() async throws {
    let fetchKey1: some SharedReaderKey<Void> = .fetch(Fetch1())
    let fetchKey2: some SharedReaderKey<Void> = .fetch(Fetch2(), animation: .default)
    #expect(fetchKey1.id.hashValue != fetchKey2.id.hashValue)
  }
}

fileprivate struct Fetch1: FetchKeyRequest {
  func fetch(_ db: Database) throws {
  }
}
fileprivate struct Fetch2: FetchKeyRequest {
  func fetch(_ db: Database) throws {
  }
}

fileprivate struct Record: Codable, Equatable, FetchableRecord, MutablePersistableRecord {
  static let databaseTableName = "records"
  let id: Int
}
extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static var database: DatabaseQueue {
    get throws {
      let database = try DatabaseQueue(named: "db")
      var migrator = DatabaseMigrator()
      migrator.registerMigration("Up") { db in
        try db.create(table: "records") { table in
          table.column("id", .integer).primaryKey(autoincrement: true)
        }
        for index in 1...3 {
          _ = try Record(id: index).inserted(db)
        }
      }
      try migrator.migrate(database)
      return database
    }
  }
}
