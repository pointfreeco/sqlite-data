import Dependencies
import SharingGRDB
import SwiftUI

struct TransactionDemo: SwiftUICaseStudy {
  let readMe = """
    This demonstrates how to use the `fetch` tool to perform multiple SQLite queries in a single \
    database transaction. If you need to fetch multiple pieces of data from the database that \
    all tend to change together, then performing those queries in a single transaction can be \
    more performant.
    
    For example, if you need to fetch rows from a table as well as a count of the rows in the \
    table, then those two pieces of data will tend to change at the same time (though not always). \
    So, it can be better to perform the select and count as two different queries in the same \
    database transaction.
    """
  let caseStudyTitle = "Database Transactions"

  @SharedReader(.fetch(Facts(), animation: .default)) private var facts = Facts.Value()

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
            _ = try Fact(body: fact).inserted(db)
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
        facts: Fact.order(Column("id").desc).fetchAll(db),
        count: Fact.fetchCount(db)
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
  static var transactionDemoDatabase: Self {
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
    $0.defaultDatabase = .transactionDemoDatabase
  }
  NavigationStack {
    CaseStudyView {
      TransactionDemo()
    }
  }
}
