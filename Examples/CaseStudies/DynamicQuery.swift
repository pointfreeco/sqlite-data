import SQLiteData
import SwiftUI

struct DynamicQueryDemo: SwiftUICaseStudy {
  let readMe = """
    This demonstrates how to perform a dynamic query with the tools of the library. Each second \
    a fact about a number is loaded from the network and saved to a database. You can search the \
    facts for text, and the list will stay in sync so that if a new fact is added to the database \
    that satisfies the search term, it will immediately appear.

    To accomplish this one can invoke the `load` method defined on the `@Fetch` projected value in \
    order to set a new query with dynamic parameters.
    """
  let caseStudyTitle = "Dynamic Query"

  @Fetch(Facts(), animation: .default) private var facts = Facts.Value()
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
        .onDelete { indices in
          withErrorReporting {
            try database.write { db in
              let ids = indices.map { facts.facts[$0].id }
              try Fact
                .where { $0.id.in(ids) }
                .delete()
                .execute(db)
            }
          }
        }
      }
    }
    .searchable(text: $query)
    .task(id: query) {
      await withErrorReporting {
        try await $facts.load(Facts(query: query), animation: .default)
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
              Fact.Draft(body: fact)
            }
            .execute(db)
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
      let search =
        Fact
        .where { $0.body.contains(query) }
        .order { $0.id.desc() }
      return try Value(
        facts: search.fetchAll(db),
        searchCount: search.fetchCount(db),
        totalCount: Fact.all.fetchCount(db)
      )
    }
  }
}

@Table
nonisolated private struct Fact: Identifiable {
  let id: Int
  var body: String
}

extension DatabaseWriter where Self == DatabaseQueue {
  static var dynamicQueryDatabase: Self {
    let databaseQueue = try! DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create 'facts' table") { db in
      try #sql(
        """
        CREATE TABLE "facts" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "body" TEXT NOT NULL
        ) STRICT
        """
      )
      .execute(db)
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
