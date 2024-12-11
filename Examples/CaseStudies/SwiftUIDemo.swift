import Dependencies
import SharingGRDB
import SwiftUI

struct SwiftUIDemo: SwiftUICaseStudy {
  let readMe = """
    This demonstrates how to use the `fetchAll` and `fetchOne` queries directly in a SwiftUI view. \
    The tools listen for changes in the database so that when the table changes it automatically \
    updates state and re-renders the view.
    
    You can also delete rows by swiping on a row and tapping the "Delete" button.
    """
  let caseStudyTitle = "SwiftUI Views"

  @SharedReader(.fetchAll(sql: #"SELECT * FROM "facts" ORDER BY "id" DESC"#, animation: .default))
  private var facts: [Fact]
  @SharedReader(.fetchOne(sql: #"SELECT count(*) FROM "facts""#, animation: .default))
  var factsCount = 0

  @Dependency(\.defaultDatabase) var database

  var body: some View {
    List {
      Section {
        Text("Facts: \(factsCount)")
          .font(.largeTitle)
          .bold()
          .contentTransition(.numericText(value: Double(factsCount)))
      }
      Section {
        ForEach(facts) { fact in
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
  static var swiftUIDatabase: Self {
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
    $0.defaultDatabase = .swiftUIDatabase
  }
  NavigationStack {
    CaseStudyView {
      SwiftUIDemo()
    }
  }
}
