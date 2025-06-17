import Dependencies
import DependenciesTestSupport
import GRDB
import Sharing
import SharingGRDB
import StructuredQueries
import Testing

@Suite(.dependency(\.defaultDatabase, try .database()))
struct FetchTests {
  @Dependency(\.defaultDatabase) var database

  @Test func bareFetchAll() async throws {
    @FetchAll var records: [Record]
    #expect(records == [Record(id: 1), Record(id: 2), Record(id: 3)])

    try await database.write { try Record.delete().execute($0) }
    try await $records.load()
    #expect(records == [])
  }

  @Test func fetchAllWithQuery() async throws {
    @FetchAll(Record.where { $0.id > 1 }) var records: [Record]
    #expect(records == [Record(id: 2), Record(id: 3)])

    try await database.write { try Record.delete().execute($0) }
    try await $records.load()
    #expect(records == [])
  }

  @Test func fetchOneCountWithQuery() async throws {
    @FetchOne(Record.where { $0.id > 1 }.count()) var recordsCount = 0
    #expect(recordsCount == 2)

    try await database.write { try Record.delete().execute($0) }
    try await $recordsCount.load()
    #expect(recordsCount == 0)
  }

  @Test func fetchOneOptional() async throws {
    @FetchOne var record: Record?
    #expect(record == Record(id: 1))
    print(#line)

    try await database.write { try Record.delete().execute($0) }
    try await $record.load()
    #expect(record == nil)
  }

  @Test func fetchOneWithDefault() async throws {
    @FetchOne var record = Record(id: 0)
    try await $record.load()
    #expect(record == Record(id: 1))

    try await database.write { try Record.delete().execute($0) }
    await #expect(throws: NotFound.self) {
      try await $record.load()
    }
    #expect($record.loadError is NotFound)
    #expect(record == Record(id: 1))
  }

  @Test func fetchOneOptional_SQL() async throws {
    @FetchOne(#sql("SELECT * FROM records LIMIT 1")) var record: Record?
    #expect(record == Record(id: 1))
    
    try await database.write { try Record.delete().execute($0) }
    try await $record.load()
    #expect(record == nil)
  }
}

@Table
private struct Record: Equatable {
  let id: Int
}
extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Up") { db in
      try #sql(
        """
        CREATE TABLE "records" ("id" INTEGER PRIMARY KEY AUTOINCREMENT)
        """
      )
      .execute(db)
      for _ in 1...3 {
        _ = try Record.insert { Record.Draft() }.execute(db)
      }
    }
    try migrator.migrate(database)
    return database
  }
}

func compileTimeTests() {
  @FetchAll(#sql("SELECT * FROM records")) var records: [Record]
  @FetchOne(#sql("SELECT count(*) FROM records")) var count = 0
  @FetchOne(#sql("SELECT * FROM records LIMIT 1")) var record: Record?
}
