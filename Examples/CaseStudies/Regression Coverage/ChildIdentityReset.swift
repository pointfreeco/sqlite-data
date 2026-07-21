import SQLiteData
import SwiftUI

struct ChildIdentityResetCaseStudy: SwiftUICaseStudy {
  let readMe = """
    This demonstrates that the `@Fetch*` tools behave like `@State` when a view's identity \
    changes: their state survives re-renders of the parent view, but is discarded and rebuilt \
    when the parent changes the child view's identity with the `id` view modifier.

    Toggle "Favorites only" in the child view to load a filtered query, then tap "Reset child \
    identity". The child view is rebuilt from scratch: the toggle returns to its default and \
    the list returns to the unfiltered query, keeping the UI and data consistent.
    """
  let caseStudyTitle = "Resetting child identity"

  @State private var resetCount = 0

  var body: some View {
    List {
      Section {
        Button("Reset child identity: \(resetCount)") {
          resetCount += 1
        }
      }
      FactsListView()
        .id(resetCount)
    }
  }
}

private struct FactsListView: View {
  @State private var isFavoritesOnly = false
  @FetchAll(Fact.all) private var facts

  var body: some View {
    Section {
      Toggle("Favorites only", isOn: $isFavoritesOnly)
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
    .task(id: isFavoritesOnly) {
      await withErrorReporting {
        if isFavoritesOnly {
          try await $facts.load(Fact.where(\.isFavorite)).task
        } else {
          try await $facts.load(Fact.all).task
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
  static var childIdentityResetDatabase: Self {
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
    $0.defaultDatabase = .childIdentityResetDatabase
  }
  NavigationStack {
    CaseStudyView {
      ChildIdentityResetCaseStudy()
    }
  }
}
