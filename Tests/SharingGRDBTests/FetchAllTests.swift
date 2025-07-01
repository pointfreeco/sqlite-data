import Combine
import Dependencies
import DependenciesTestSupport
import Foundation
import GRDB
import Sharing
import SharingGRDB
import StructuredQueries
import Testing

@Suite(.dependency(\.defaultDatabase, try .database()))
struct FetchAllTests {
  @Dependency(\.defaultDatabase) var database

  @MainActor
  @Test func concurrency() async throws {
    let count = 1_000
    try await database.write { db in
      try Record.delete().execute(db)
    }

    @FetchAll var records: [Record]

    await withThrowingTaskGroup { group in
      for index in 1...count {
        group.addTask {
          try await database.write { db in
            try Record.insert { Record(id: index) }.execute(db)
          }
        }
      }
    }

    try await $records.load()
    #expect(records == (1...count).map { Record(id: $0) })

    await withThrowingTaskGroup { group in
      for index in 1...(count / 2) {
        group.addTask {
          try await database.write { db in
            try Record.find(index * 2).delete().execute(db)
          }
        }
      }
    }

    try await $records.load()
    #expect(records == (0...(count / 2 - 1)).map { Record(id: $0 * 2 + 1) })
  }

  @available(iOS 17, macOS 14, tvOS 17, watchOS 10, *)
  @Test func fetchFailure() {
    do {
      try database.read { db in
        _ =
          try Record
          .select { ($0.id, $0.date, #sql("\($0.optionalDate)", as: Date.self)) }
          .fetchAll(db)
      }
      Issue.record()
    } catch {
      #expect(
        "\(error)".contains(
          """
          Expected column 2 ("optionalDate") to not be NULL
          """
        )
      )
    }
  }
}

@Table
private struct Record: Equatable {
  let id: Int
  @Column(as: Date.UnixTimeRepresentation.self)
  var date = Date(timeIntervalSince1970: 42)
  @Column(as: Date?.UnixTimeRepresentation.self)
  var optionalDate: Date?
}
extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> DatabaseQueue {
    let database = try DatabaseQueue()
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "records" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "date" INTEGER NOT NULL DEFAULT 42,
          "optionalDate" INTEGER
        )
        """
      )
      .execute(db)
      for _ in 1...3 {
        _ = try Record.insert { Record.Draft() }.execute(db)
      }
    }
    return database
  }
}
