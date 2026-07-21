import GRDB
import SQLiteData
import SwiftUI

struct ParentRerenderLoadedDataCaseStudy: SwiftUICaseStudy {
  let readMe = """
    This demonstrates that data loaded by the `@Fetch*` tools survives a parent view re-render.

    The child view below has a `@Fetch` property that begins with an empty default value and is \
    loaded in the view's `task`. Tapping the stepper changes `@State` in the parent view, which \
    causes the child view (and its `@Fetch`) to be re-initialized. The facts should remain on \
    screen, and should not revert to the empty default value. The same is true when any other \
    dynamic property in the parent changes, such as `@Environment`.
    """
  let caseStudyTitle = "Loaded data with re-rendered parent"

  @State private var count = 0

  var body: some View {
    List {
      Section {
        Stepper("Parent state: \(count)", value: $count)
      }
      FactsListView(count: count)
    }
  }
}

private struct FactsListView: View {
  let count: Int
  @Fetch private var facts = Facts.Value()

  var body: some View {
    Section("Facts (parent state: \(count))") {
      if facts.facts.isEmpty {
        Text("No facts loaded")
      }
      ForEach(facts.facts) { fact in
        Text(fact.body)
      }
    }
    .task {
      await withErrorReporting {
        try await $facts.load(Facts()).task
      }
    }
  }

  private struct Facts: FetchKeyRequest {
    struct Value {
      var facts: [Fact] = []
    }
    func fetch(_ db: Database) throws -> Value {
      try Value(facts: Fact.order { $0.id.desc() }.fetchAll(db))
    }
  }
}

@Table
nonisolated private struct Fact: Identifiable {
  let id: Int
  var body: String
}

extension DatabaseWriter where Self == DatabaseQueue {
  static var parentRerenderLoadedDataDatabase: Self {
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
      try Fact.insert {
        Fact.Draft(body: "SQLite was first released in the year 2000.")
        Fact.Draft(body: "SQLite is the most widely deployed database in the world.")
        Fact.Draft(body: "SQLite is a C library, not a client-server database.")
      }
      .execute(db)
    }
    try! migrator.migrate(databaseQueue)
    return databaseQueue
  }
}

#Preview {
  let _ = prepareDependencies {
    $0.defaultDatabase = .parentRerenderLoadedDataDatabase
  }
  NavigationStack {
    CaseStudyView {
      ParentRerenderLoadedDataCaseStudy()
    }
  }
}
