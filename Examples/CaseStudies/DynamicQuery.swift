import Dependencies
import SharingGRDB
import SwiftUI

struct DynamicQueryDemo: SwiftUICaseStudy {
  let readMe = """
    This demonstrates how to perform a dynamic query with the tools of the library. Each second \
    a fact about a number is loaded from the network and saved to a database. You can search the \
    facts for text, and the list will stay in sync so that if a new fact is added to the database \
    that satisfies the search term, it will immediately appear.
    
    To accomplish this one can invoke the `load` method defined on the `@SharedReader` projected \
    value in order to set a new query with dynamic parameters.
    """
  let caseStudyTitle = "Dynamic Query"

  @State.SharedReader(.fetch(Facts(), animation: .default)) private var facts = Facts.Value()
  @State var query = ""

  @Dependency(\.defaultDatabase) var database

  var body: some View {
    List {
      Section {
        if query.isEmpty {
          Text("Facts: \(facts.totalCount)")
            .contentTransition(.numericText(value: Double(facts.totalCount)))
            .font(.largeTitle)
            .bold()
        } else {
          Text("Search: \(facts.searchCount)")
            .contentTransition(.numericText(value: Double(facts.searchCount)))
          Text("Facts: \(facts.totalCount)")
            .contentTransition(.numericText(value: Double(facts.totalCount)))
        }
      }
      Section {
        ForEach(facts.facts) { fact in
          Text(fact.body)
        }
        .onDelete { indexSet in
          withErrorReporting {
            try database.write { db in
              _ = try Fact.deleteAll(db, ids: indexSet.compactMap { facts.facts[$0].id })
            }
          }
        }
      }
    }
    .searchable(text: $query)
    .task(id: query) {
      await withErrorReporting {
        try await $facts.load(.fetch(Facts(query: query), animation: .default))
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

  private struct Facts: FetchKeyRequest {
    var query = ""
    struct Value {
      var facts: [Fact] = []
      var searchCount = 0
      var totalCount = 0
    }
    func fetch(_ db: Database) throws -> Value {
      let query = Fact.order(Column("id").desc).filter(Column("body").like("%\(query)%"))
      return try Value(
        facts: query.fetchAll(db),
        searchCount: query.fetchCount(db),
        totalCount: Fact.fetchCount(db)
      )
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
  static var dynamicQueryDatabase: Self {
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
    $0.defaultDatabase = .dynamicQueryDatabase
  }
  NavigationStack {
    CaseStudyView {
      DynamicQueryDemo()
    }
  }
}
