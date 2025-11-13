import DependenciesTestSupport
import Foundation
import SQLiteData
import Testing

@Suite(.dependency(\.defaultDatabase, try .database())) struct FetchTaskTests {
  @Dependency(\.defaultDatabase) var database

  @Test func stopSubscriptionWhenTaskCancelled() async throws {
    @FetchAll var records: [Record]
    #expect(records.count == 0)

    try await database.write { db in
      try Record.insert { Record.Draft() }.execute(db)
    }
    try await $records.load()
    #expect(records.count == 1)

    let task = Task { [$records] in
      try? await $records.load(Record.all).task
    }
    task.cancel()
    await task.value
    try await database.write { db in
      try Record.insert { Record.Draft() }.execute(db)
    }
    try await $records.load()
    #expect(records.count == 1)
  }
}

@Table
private struct Record: Equatable {
  let id: Int
}
extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "records" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT
        )
        """
      )
      .execute(db)
    }
    return database
  }
}
