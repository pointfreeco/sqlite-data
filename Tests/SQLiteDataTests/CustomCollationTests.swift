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
}
