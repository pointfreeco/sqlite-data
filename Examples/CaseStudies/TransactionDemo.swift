import SQLiteData
import SwiftUI

struct TransactionDemo: SwiftUICaseStudy {
  let readMe = """
    This demonstrates how to use the `@Fetch` tool to perform multiple SQLite queries in a single \
    database transaction. If you need to fetch multiple pieces of data from the database that \
    all tend to change together, then performing those queries in a single transaction can be \
    more performant.

    For example, if you need to fetch rows from a table as well as a count of the rows in the \
    table, then those two pieces of data will tend to change at the same time (though not always). \
    So, it can be better to perform the select and count as two different queries in the same \
    database transaction.
    """
  let caseStudyTitle = "Database Transactions"

  @Fetch(Facts(), animation: .default)
  private var facts = Facts.Value()

  @Dependency(\.defaultDatabase) var database

  var body: some View {
    List {
      Section {
        Text("Facts: \(facts.count)")
          .font(.largeTitle)
          .bold()
          .contentTransition(.numericText(value: Double(facts.count)))
      }
      Section {
        ForEach(facts.facts) { fact in
          Text(fact.body)
        }
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
    struct Value {
      var facts: [Fact] = []
      var count = 0
    }
    func fetch(_ db: Database) throws -> Value {
      try Value(
        facts: Fact.order { $0.id.desc() }.fetchAll(db),
        count: Fact.all.fetchCount(db)
      )
    }
  }
}

@Table
private struct Fact: Identifiable {
  static let databaseTableName = "facts"
  let id: Int
  var body: String
}

extension DatabaseWriter where Self == DatabaseQueue {
  static var transactionDemoDatabase: Self {
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
    $0.defaultDatabase = .transactionDemoDatabase
  }
  NavigationStack {
    CaseStudyView {
      TransactionDemo()
    }
  }
}
