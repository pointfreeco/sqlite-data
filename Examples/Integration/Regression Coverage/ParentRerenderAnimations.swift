import SQLiteData
import SwiftUI

struct ParentRerenderAnimationsCaseStudy: SwiftUICaseStudy {
  let readMe = """
    This demonstrates that animations provided to the `@Fetch*` tools continue to work after a \
    parent view re-renders.

    The list below is loaded in the child view's `task` with an `animation` parameter, and so \
    tapping "Add fact" animates the new fact into the list. Tapping "Re-render parent" changes \
    `@State` in the parent view, which causes the child view (and its `@FetchAll`) to be \
    re-initialized. Adding a fact should continue to animate afterwards.
    """
  let caseStudyTitle = "Animations with re-rendered parent"

  @State private var rerenderCount = 0
  @Dependency(\.defaultDatabase) var database

  var body: some View {
    List {
      Section {
        Button("Re-render parent: \(rerenderCount)") {
          rerenderCount += 1
        }
        Button("Add fact") {
          withErrorReporting {
            try database.write { db in
              try Fact.insert {
                Fact.Draft(body: Date.now.formatted(date: .omitted, time: .standard))
              }
              .execute(db)
            }
          }
        }
      }
      FactsListView()
    }
  }
}

private struct FactsListView: View {
  @FetchAll(Fact.order { $0.id.desc() })
  private var facts

  var body: some View {
    Section {
      ForEach(facts) { fact in
        Text(fact.body)
      }
    }
    .task {
      await withErrorReporting {
        try await $facts.load(Fact.order { $0.id.desc() }, animation: .default).task
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
  static var parentRerenderAnimationsDatabase: Self {
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
    $0.defaultDatabase = .parentRerenderAnimationsDatabase
  }
  NavigationStack {
    CaseStudyView {
      ParentRerenderAnimationsCaseStudy()
    }
  }
}
