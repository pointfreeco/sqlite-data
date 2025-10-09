import SQLiteData
import SwiftUI

struct ObservableModelDemo: SwiftUICaseStudy {
  let readMe = """
    This demonstrates how to use the `@FetchAll` and `@FetchOne` tools in an `@Observable` model. \
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
  @FetchAll(Fact.order { $0.id.desc() }, animation: .default)
  var facts
  @ObservationIgnored
  @FetchOne(Fact.count(), animation: .default)
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
        try Fact.insert {
          Fact.Draft(body: fact)
        }
        .execute(db)
      }
    }
  }

  func deleteFact(indices: IndexSet) {
    withErrorReporting {
      try database.write { db in
        let ids = indices.map { facts[$0].id }
        try Fact
          .where { $0.id.in(ids) }
          .delete()
          .execute(db)
      }
    }
  }
}

@Table
nonisolated private struct Fact: Identifiable {
  let id: Int
  var body: String
}

extension DatabaseWriter where Self == DatabaseQueue {
  static var observableModelDatabase: Self {
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
    $0.defaultDatabase = .observableModelDatabase
  }
  NavigationStack {
    CaseStudyView {
      ObservableModelDemo()
    }
  }
}
