import Dependencies
import SharingGRDB
import SwiftUI

struct AnimationsCaseStudy: SwiftUICaseStudy {
  let readMe = """
    This demonstrates how to animate fetching data from the database, or when data changes in \
    the database. Simply provide the `animation` argument to `fetchAll` (or the other querying \
    tools, such as `fetch` and `fetchOne`). 
    
    This is analogous to how animations work in SwiftData in which one provides an `animation` \
    argument to the `@Query` macro.
    """
  let caseStudyTitle = "Animations"

  @SharedReader(.fetchAll(sql: #"SELECT * FROM "facts" ORDER BY "id" DESC"#, animation: .default))
  private var facts: [Fact]

  @Dependency(\.defaultDatabase) var database

  var body: some View {
    List {
      ForEach(facts) { fact in
        Text(fact.body)
      }
    }
    .task {
      do {
        var number = 0
        while true {
          try await Task.sleep(for: .seconds(1))
          number += 1
          let fact = try await String(
            decoding: URLSession.shared
              .data(from: URL(string: "http://numberapi.com/\(number)")!).0,
            as: UTF8.self
          )
          try await database.write { db in
            _ = try Fact(body: fact).inserted(db)
          }
        }
      } catch {}
    }
  }
}

private struct Fact: Codable, FetchableRecord, Identifiable, MutablePersistableRecord {
  static let databaseTableName = "facts"
  var id: Int64?
  var body: String
  mutating func didInsert(_ inserted: InsertionSuccess) {
    id = inserted.rowID
  }
}

extension DatabaseWriter where Self == DatabaseQueue {
  static var animationDatabase: Self {
    let databaseQueue = try! DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create 'facts' table") { db in
      try db.create(table: Fact.databaseTableName) { table in
        table.autoIncrementedPrimaryKey("id")
        table.column("body", .text).notNull()
      }
    }
    try! migrator.migrate(databaseQueue)
    return databaseQueue
  }
}

#Preview {
  let _ = prepareDependencies {
    $0.defaultDatabase = .animationDatabase
  }
  NavigationStack {
    CaseStudyView {
      AnimationsCaseStudy()
    }
  }
}
