import GRDB
import SQLiteData
import SwiftUI

struct ParentRerenderLoadErrorCaseStudy: SwiftUICaseStudy {
  let readMe = """
    This demonstrates that a load error survives a parent view re-render.

    The child view below loads a query that always fails, and so it renders the `loadError` of \
    its `@Fetch` property. Tapping the stepper changes `@State` in the parent view, which causes \
    the child view (and its `@Fetch`) to be re-initialized. The error should remain on screen, \
    and should not be silently discarded, which would make the view appear healthy even though \
    its query failed.
    """
  let caseStudyTitle = "Load errors with re-rendered parent"

  @State private var count = 0

  var body: some View {
    List {
      Section {
        Stepper("Parent state: \(count)", value: $count)
      }
      FactsView(count: count)
    }
  }
}

private struct FactsView: View {
  let count: Int
  @Fetch private var facts = Facts.Value()

  var body: some View {
    Section("Facts (parent state: \(count))") {
      if let loadError = $facts.loadError {
        Label(loadError.localizedDescription, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
      } else {
        Text("Facts: \(facts.count)")
      }
    }
    .task {
      try? await $facts.load(Facts())
    }
  }

  private struct Facts: FetchKeyRequest {
    struct Value {
      var count = 0
    }
    func fetch(_ db: Database) throws -> Value {
      struct QueryFailure: LocalizedError {
        var errorDescription: String? { "Something went wrong." }
      }
      throw QueryFailure()
    }
  }
}

extension DatabaseWriter where Self == DatabaseQueue {
  static var parentRerenderLoadErrorDatabase: Self {
    try! DatabaseQueue()
  }
}

#Preview {
  let _ = prepareDependencies {
    $0.defaultDatabase = .parentRerenderLoadErrorDatabase
  }
  NavigationStack {
    CaseStudyView {
      ParentRerenderLoadErrorCaseStudy()
    }
  }
}
