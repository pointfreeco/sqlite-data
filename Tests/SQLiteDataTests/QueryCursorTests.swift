import SQLiteData
import Testing

@Suite struct QueryCursorTests {
  let database: DatabaseQueue
  init() throws {
    database = try DatabaseQueue()
    try database.write { db in
      try #sql(#"CREATE TABLE "numbers" ("value" INTEGER NOT NULL)"#)
        .execute(db)
    }
  }

  @Test func emptyInsert() throws {
    try database.write { db in
      try Number.insert { [] }.execute(db)
    }
  }

  @Test func emptyUpdate() throws {
    try database.write { db in
      try Number.update { _ in }.execute(db)
    }
  }
}

@Table private struct Number {
  var value = 0
}
