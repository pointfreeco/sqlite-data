import SQLiteData
import SwiftUI

struct SectionedQueryDemo: SwiftUICaseStudy {
  let readMe = """
    This demonstrates how to group the results of a `@FetchAll` query into sections by providing \
    a `sectionBy:` argument. Results are ordered and grouped into a section for each distinct \
    value of the sectioning expression, and the sections are accessed from the property's \
    projected value.

    Use the picker to change how the reminders are sectioned: by category, by priority, or with \
    no sectioning at all. This is done by invoking the `load` method defined on the `@FetchAll` \
    projected value with a `sectionBy:` closure that can return a different expression depending \
    on state, or `nil` for no grouping. Reminders without a priority are grouped into a section \
    with a `nil` name. You can also delete rows by swiping on a row and tapping the "Delete" \
    button.
    """
  let caseStudyTitle = "Sectioned Queries"

  @FetchAll(Reminder.order(by: \.title), sectionBy: \.category, animation: .default)
  private var reminders

  @State private var sectioning = Sectioning.category

  @Dependency(\.defaultDatabase) var database

  private enum Sectioning: String, CaseIterable {
    case none = "None"
    case category = "Category"
    case priority = "Priority"
  }

  var body: some View {
    List {
      Section {
        Picker("Section by", selection: $sectioning) {
          ForEach(Sectioning.allCases, id: \.self) { sectioning in
            Text(sectioning.rawValue)
          }
        }
        .pickerStyle(.segmented)
      }
      ForEach($reminders.sections) { section in
        Section {
          ForEach(section) { reminder in
            Text(reminder.title)
          }
          .onDelete { indices in
            withErrorReporting {
              try database.write { db in
                let ids = indices.map { section[$0].id }
                try Reminder
                  .where { $0.id.in(ids) }
                  .delete()
                  .execute(db)
              }
            }
          }
        } header: {
          if let name = section.name {
            Text(name)
          }
        }
      }
    }
    .task(id: sectioning) {
      await withErrorReporting {
        try await $reminders.load(
          Reminder.order(by: \.title),
          sectionBy: {
            switch sectioning {
            case .none:
              nil
            case .category:
              $0.category
            case .priority:
              $0.priority.asc(nulls: .last)
            }
          },
          animation: .default
        )
      }
    }
  }
}

@Table
nonisolated private struct Reminder: Identifiable {
  let id: Int
  var title: String
  var category: String
  var priority: String?
}

extension DatabaseWriter where Self == DatabaseQueue {
  static var sectionedQueryDatabase: Self {
    let databaseQueue = try! DatabaseQueue()
    var migrator = DatabaseMigrator()
    migrator.registerMigration("Create 'reminders' table") { db in
      try #sql(
        """
        CREATE TABLE "reminders" (
          "id" INTEGER PRIMARY KEY AUTOINCREMENT,
          "title" TEXT NOT NULL,
          "category" TEXT NOT NULL,
          "priority" TEXT
        ) STRICT
        """
      )
      .execute(db)
    }
    migrator.registerMigration("Seed 'reminders' table") { db in
      try Reminder.insert {
        Reminder.Draft(title: "Call mom", category: "Family", priority: "High")
        Reminder.Draft(title: "Plan vacation", category: "Family")
        Reminder.Draft(title: "Buy groceries", category: "Personal", priority: "High")
        Reminder.Draft(title: "Go to the gym", category: "Personal", priority: "Low")
        Reminder.Draft(title: "Pick up dry cleaning", category: "Personal")
        Reminder.Draft(title: "Prepare talk", category: "Work", priority: "High")
        Reminder.Draft(title: "Send status report", category: "Work", priority: "Low")
      }
      .execute(db)
    }
    try! migrator.migrate(databaseQueue)
    return databaseQueue
  }
}

#Preview {
  let _ = prepareDependencies {
    $0.defaultDatabase = .sectionedQueryDatabase
  }
  NavigationStack {
    CaseStudyView {
      SectionedQueryDemo()
    }
  }
}
