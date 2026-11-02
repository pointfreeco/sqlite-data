import DependenciesTestSupport
import Foundation
import SQLiteData
import SQLiteDataTestSupport
import Testing

struct DatabaseFunctionTests {
  @DatabaseFunction
  func exclaim(_ text: String) -> String {
    text + "!"
  }
  @Test func scalarFunction() async throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.add(function: $exclaim)
    }
    let database = try DatabaseQueue(configuration: configuration)
    assertQuery(Values($exclaim("Blob")), database: database) {
      """
      ┌─────────┐
      │ "Blob!" │
      └─────────┘
      """
    }
  }

  @Test(.dependency(\.defaultDatabase, try .database())) func aggregateFunction() async throws {
    assertQuery(Record.select { $sum($0.id) }) {
      """
      ┌───┐
      │ 6 │
      └───┘
      """
    }
  }
}

@Table
private struct Record: Equatable {
  let id: Int
}

@DatabaseFunction
func sum(_ xs: some Sequence<Int>) -> Int {
  xs.reduce(0, +)
}

extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> DatabaseQueue {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.add(function: $sum)
    }
    let database = try DatabaseQueue(configuration: configuration)
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "records" (
          "id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT
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
