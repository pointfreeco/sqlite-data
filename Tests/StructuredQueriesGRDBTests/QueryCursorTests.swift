import GRDB
import StructuredQueriesGRDB
import Testing

@Suite struct QueryCursorTests {
  let database: DatabaseQueue
  init() throws {
    var configuration = Configuration()
    configuration.prepareDatabase {
      $0.trace { print($0) }
    }
    database = try DatabaseQueue(configuration: configuration)
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
