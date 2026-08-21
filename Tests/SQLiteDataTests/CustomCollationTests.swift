import Foundation
import SQLiteData
import Testing

@Suite struct CustomCollationsTests {
  @Table struct Item {
    var title: String
  }

  @DatabaseCollation func reversed(_ lhs: String, _ rhs: String) -> CollationOrder {
    CollationOrder(rhs, lhs)
  }

  @Test func basics() throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.add(collation: $reversed)
    }
    let database = try DatabaseQueue(configuration: configuration)
    let titles = try database.write { db in
      try db.execute(sql: "CREATE TABLE items (title TEXT NOT NULL)")
      try db.execute(sql: "INSERT INTO items VALUES ('a'), ('c'), ('b')")
      return try Item.order { $0.title.collate($reversed) }.fetchAll(db).map(\.title)
    }
    #expect(titles == ["c", "b", "a"])

    try database.write { db in
      db.remove(collation: $reversed)
    }
    #expect(throws: (any Error).self) {
      try database.read { db in
        _ = try Item.order { $0.title.collate($reversed) }.fetchAll(db)
      }
    }
  }

  @Suite(.dependency(\.defaultDatabase, try .database()))
  struct CanonicalCollationTests {
    @Dependency(\.defaultDatabase) var database

    @Table struct Item {
      var title: String
    }

    @Test func ordering() throws {
      let titles = ["cafe\u{0301}z", "CAFE", "caf\u{00E9}", "caff", "cafe"]
      try database.write { db in
        try Item.insert {
          for title in titles {
            Item(title: title)
          }
        }
        .execute(db)
      }
      let ordered = try database.read { db in
        try Item.order { $0.title.collate(.canonical) }.fetchAll(db).map(\.title)
      }
      #expect(ordered == titles.sorted())
    }

    @Test func equality() throws {
      try database.write { db in
        try Item.insert {
          for title in ["caf\u{00E9}", "cafe\u{0301}", "cafe"] {
            Item(title: title)
          }
        }
        .execute(db)
      }
      let matches = try database.read { db in
        try Item.where { $0.title.collate(.canonical).eq("caf\u{00E9}") }.fetchAll(db)
      }
      #expect(matches.count == 2)
    }

  }
}

extension DatabaseWriter where Self == DatabaseQueue {
  fileprivate static func database() throws -> any DatabaseWriter {
    let database = try SQLiteData.defaultDatabase()
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "items" ("title" TEXT NOT NULL)
        """
      )
      .execute(db)
    }
    return database
  }
}
