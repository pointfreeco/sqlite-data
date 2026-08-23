import SQLiteData
import SwiftUI

struct ParentRerenderCancellationCaseStudy: SwiftUICaseStudy {
  let readMe = """
    This demonstrates that a cancelled observation survives a parent view re-render.

    The child view below observes a list of facts that grows every second, and toggling "Live \
    updates" off cancels the observation using the subscription's `task`, freezing the list. \
    Tapping "Re-render parent" changes `@State` in the parent view, which causes the child view \
    (and its `@FetchAll`) to be re-initialized. The list should remain frozen, and should not \
    silently resume live updates while the toggle remains off.
    """
  let caseStudyTitle = "Cancellation with re-rendered parent"

  @State private var rerenderCount = 0

  var body: some View {
    List {
      Section {
        Button("Re-render parent: \(rerenderCount)") {
          rerenderCount += 1
        }
      }
      FactsListView()
    }
  }
}

private struct FactsListView: View {
  @State private var isLive = true
  @FetchAll(Fact.order { $0.id.desc() })
  private var facts
  @Dependency(\.defaultDatabase) var database

  var body: some View {
    Section {
      Toggle("Live updates", isOn: $isLive)
      ForEach(facts) { fact in
        Text(fact.body)
      }
    }
    .task(id: isLive) {
      guard isLive else { return }
      await withErrorReporting {
        try await $facts.load(Fact.order { $0.id.desc() }).task
      }
    }
    .task {
      do {
        while true {
          try await Task.sleep(for: .seconds(1))
          try await database.write { db in
            try Fact.insert {
              Fact.Draft(body: Date.now.formatted(date: .omitted, time: .standard))
            }
            .execute(db)
          }
        }
      } catch {}
    }
  }
}

@Table
nonisolated private struct Fact: Identifiable {
  let id: Int
  var body: String
}

extension DatabaseWriter where Self == DatabaseQueue {
  static var parentRerenderCancellationDatabase: Self {
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
    $0.defaultDatabase = .parentRerenderCancellationDatabase
  }
  NavigationStack {
    CaseStudyView {
      ParentRerenderCancellationCaseStudy()
    }
  }
}
