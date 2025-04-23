import Dependencies
import DependenciesTestSupport
import GRDB
import Sharing
import SharingGRDB
import StructuredQueries
import SwiftUI
import Testing

@Suite(.dependency(\.defaultDatabase, try .database()))
struct FetchTests {
  @Test func bareFetchAll() async throws {
    @FetchAll var records: [Record]
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(records == [Record(id: 1), Record(id: 2), Record(id: 3)])
  }

  @Test func fetchAllWithQuery() async throws {
    @FetchAll(Record.where { $0.id > 1 }) var records: [Record]
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(records == [Record(id: 2), Record(id: 3)])
  }

  @Test func bareFetchCount() async throws {
    @FetchOne var recordsCount = 0
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(recordsCount == 3)
  }

  @Test func fetchCountWithQuery() async throws {
    @FetchOne(Record.where { $0.id > 1 }.count()) var recordsCount = 0
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(recordsCount == 2)
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
        _ = try Record.insert(Record.Draft()).execute(db)
      }
    }
    try migrator.migrate(database)
    return database
  }
}
