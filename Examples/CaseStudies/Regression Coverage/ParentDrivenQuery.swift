import SQLiteData
import SwiftUI

struct ParentDrivenQueryCaseStudy: SwiftUICaseStudy {
  let readMe = """
    This demonstrates how to drive a child view's query from parent state by constructing the \
    `@FetchAll` in the child's initializer, analogous to constructing a SwiftData `@Query` with a \
    dynamic predicate in a view's initializer.

    Toggling "Favorites only" re-initializes the child view with a different query, and the child \
    should immediately display the results of the new query. Tapping "Re-render parent" \
    re-initializes the child with the same query, which should have no effect.
    """
  let caseStudyTitle = "Parent-driven queries"

  @State private var isFavoritesOnly = false
  @State private var rerenderCount = 0

  var body: some View {
    List {
      Section {
        Toggle("Favorites only", isOn: $isFavoritesOnly)
        Button("Re-render parent: \(rerenderCount)") {
          rerenderCount += 1
        }
      }
      FactsListView(isFavoritesOnly: isFavoritesOnly)
    }
  }
}

private struct FactsListView: View {
  @FetchAll private var facts: [Fact]

  init(isFavoritesOnly: Bool) {
    if isFavoritesOnly {
      _facts = FetchAll(Fact.where(\.isFavorite))
    } else {
      _facts = FetchAll(Fact.all)
    }
  }

  var body: some View {
    Section {
      ForEach(facts) { fact in
        HStack {
          Text(fact.body)
          Spacer()
          if fact.isFavorite {
            Image(systemName: "star.fill")
              .foregroundStyle(.yellow)
          }
        }
      }
    }
  }
}

@Table
nonisolated private struct Fact: Identifiable {
  let id: Int
  var body: String
  var isFavorite = false
}

extension DatabaseWriter where Self == DatabaseQueue {
  static var parentDrivenQueryDatabase: Self {
    let databaseQueue = try! DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create 'facts' table") { db in
      try #sql(
        """
        CREATE TABLE "facts" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "body" TEXT NOT NULL,
          "isFavorite" INTEGER NOT NULL DEFAULT 0
        ) STRICT
        """
      )
      .execute(db)
      try Fact.insert {
        Fact.Draft(body: "SQLite was first released in the year 2000.", isFavorite: true)
        Fact.Draft(body: "SQLite is the most widely deployed database in the world.")
        Fact.Draft(body: "SQLite is a C library, not a client-server database.", isFavorite: true)
        Fact.Draft(body: "SQLite databases are a single file on disk.")
      }
      .execute(db)
    }
    try! migrator.migrate(databaseQueue)
    return databaseQueue
  }
}

#Preview {
  let _ = prepareDependencies {
    $0.defaultDatabase = .parentDrivenQueryDatabase
  }
  NavigationStack {
    CaseStudyView {
      ParentDrivenQueryCaseStudy()
    }
  }
}
