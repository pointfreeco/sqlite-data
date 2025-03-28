import Dependencies
import SharingGRDB
import StructuredQueriesGRDB
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

  @SharedReader(.fetchAll(Fact.order { $0.id.desc() }, animation: .default))
  private var facts

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
            try Fact.insert {
              $0.body
            } values: {
              fact
            }
            .execute(db)
          }
        }
      } catch {}
    }
  }
}

@Table
private struct Fact: Identifiable {
  let id: Int64
  var body: String
}

extension DatabaseWriter where Self == DatabaseQueue {
  static var animationDatabase: Self {
    let databaseQueue = try! DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create 'facts' table") { db in
      try db.create(table: Fact.tableName) { table in
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
