import Dependencies
import SharingGRDB
import SwiftUI

struct ObservableModelDemo: SwiftUICaseStudy {
  let readMe = """
    This demonstrates how to use the `fetchAll` and `fetchOne` tools in an @Observable model. \
    In SwiftUI, the `@Query` macro only works when installed directly in a SwiftUI view, and \
    cannot be used outside of views.
    
    The tools provided with this library work basically anywhere, including in `@Observable` \
    models and UIKit view controllers.
    """
  let caseStudyTitle = "@Observable Model"

  @State private var model = Model()

  var body: some View {
    List {
      Section {
        Text("Facts: \(model.factsCount)")
          .font(.largeTitle)
          .bold()
          .contentTransition(.numericText(value: Double(model.factsCount)))
      }
      Section {
        ForEach(model.facts) { fact in
          Text(fact.body)
        }
        .onDelete { indices in
          model.deleteFact(indices: indices)
        }
      }
    }
    .task {
      do {
        while true {
          try await Task.sleep(for: .seconds(1))
          await model.increment()
        }
      } catch {}
    }
  }
}

@Observable
@MainActor
private class Model {
  @ObservationIgnored
  @SharedReader(.fetchAll(sql: #"SELECT * FROM "facts" ORDER BY "id" DESC"#, animation: .default))
  var facts: [Fact]
  @ObservationIgnored
  @SharedReader(.fetchOne(sql: #"SELECT count(*) FROM "facts""#, animation: .default))
  var factsCount = 0
  var number = 0

  @ObservationIgnored
  @Dependency(\.defaultDatabase) var database

  func increment() async {
    number += 1
    await withErrorReporting {
      let fact = try await String(
        decoding: URLSession.shared
          .data(from: URL(string: "http://numberapi.com/\(number)")!).0,
        as: UTF8.self
      )
      try await database.write { db in
        _ = try Fact(body: fact).inserted(db)
      }
    }
  }

  func deleteFact(indices: IndexSet) {
    _ = withErrorReporting {
      try database.write { db in
        try Fact.deleteAll(db, ids: indices.compactMap { facts[$0].id })
      }
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
  static var observableModelDatabase: Self {
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
    $0.defaultDatabase = .observableModelDatabase
  }
  NavigationStack {
    CaseStudyView {
      ObservableModelDemo()
    }
  }
}
