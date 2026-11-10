import Foundation
import SQLiteData
import Testing

@Suite struct JSONBTests {
  @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
  @DatabaseFunction(as: ((AttributedString.JSONBRepresentation) -> String).self)
  private func string(from attributedString: AttributedString) -> String {
    String(attributedString.characters[...])
  }
  
  @available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
  @Test func databaseFunctionWithJSONBArgument() throws {
    var configuration = Configuration()
    configuration.prepareDatabase { db in
      db.add(function: $string)
    }
    let database = try DatabaseQueue(configuration: configuration)
    
    try database.write { db in
      try #sql(
        """
        CREATE TABLE "items" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "text" BLOB NOT NULL
        ) STRICT
        """
      )
      .execute(db)
    }
    
    try database.write { db in
      try Item.insert {
        Item.Draft(text: AttributedString("blob"))
      }.execute(db)
      
      _ = try Item.all
        .select { $string($0.text) }
        .fetchOne(db)
    }
  }
}

@available(iOS 26, macOS 26, tvOS 26, watchOS 26, *)
@Table
private struct Item: Identifiable {
  let id: Int
  @Column(as: AttributedString.JSONBRepresentation.self)
  var text: AttributedString
}
