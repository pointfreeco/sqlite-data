import Benchmark
import Foundation
import GRDB
import SQLiteData

let batchSize = 10_000

let benchmarks : @Sendable () -> Void = {
  Benchmark("GRDB: Bulk insert") { benchmark in
    let database = try database()
    for _ in benchmark.scaledIterations {
      try database.write { db in
        defer { precondition(try! Reminder.all.count().fetchOne(db) == batchSize) }

        let stmt = try db.makeStatement(
          sql: """
            INSERT INTO "reminders" ("id", "title", "isCompleted")
            VALUES (?, ?, ?)
            """
        )
        for index in 1...batchSize {
          let args: [any DatabaseValueConvertible] = [index, "", false]
          stmt.setUncheckedArguments(StatementArguments(args))
          try stmt.execute()
        }
      }
    }
  }

  Benchmark("SQLiteData: Bulk insert") { benchmark in
    let database = try database()
    for _ in benchmark.scaledIterations {
      try database.write { db in
        defer { precondition(try! Reminder.all.count().fetchOne(db) == batchSize) }

        try Reminder.insert {
          for index in 1...batchSize {
            Reminder(id: index)
          }
        }
        .execute(db)
      }
    }
  }

//  Benchmark("SQLiteData: Individual insert") { benchmark in
//    let database = try database()
//    for _ in benchmark.scaledIterations {
//      try database.write { db in
//        defer { precondition(try! Reminder.all.count().fetchOne(db) == batchSize) }
//
//        for index in 1...batchSize {
//          try Reminder.insert {
//            Reminder(id: index)
//          }
//          .execute(db)
//        }
//      }
//    }
//  }
}

@Table struct Reminder {
  let id: Int
  var title = ""
  var isCompleted = false
}
func database() throws -> any DatabaseWriter {
  let database = try DatabasePool(
    path: URL.temporaryDirectory.appending(path: UUID().uuidString).path(),
    configuration: Configuration()
  )
  try database.write { db in
    try #sql(
      """
      CREATE TABLE "reminders" (
        "id" INTEGER PRIMARY KEY AUTOINCREMENT,
        "title" TEXT NOT NULL DEFAULT '',
        "isCompleted" INTEGER NOT NULL DEFAULT 0
      ) STRICT
      """
    )
    .execute(db)
  }
  return database
}
