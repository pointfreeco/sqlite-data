import IssueReporting
import SharingGRDB
import SwiftUI

@MainActor
@Observable
class SearchRemindersModel {
  var showCompletedInSearchResults = false
  var searchText = "" {
    didSet {
      Task { await updateQuery() }
    }
  }

  @ObservationIgnored @FetchOne var completedCount: Int = 0
  @ObservationIgnored @FetchAll var reminders: [Row]

  @ObservationIgnored @Dependency(\.defaultDatabase) private var database

  func showCompletedButtonTapped() async {
    showCompletedInSearchResults.toggle()
    await updateQuery()
  }

  func deleteCompletedReminders(monthsAgo: Int? = nil) {
    withErrorReporting {
      try database.write { db in
        try Reminder
          .where { $0.isCompleted && $0.id.in(baseQuery.select { reminder, _ in reminder.id }) }
          .where {
            if let monthsAgo {
              #sql("\($0.dueDate) < date('now', '-\(raw: monthsAgo) months')")
            }
          }
          .delete()
          .execute(db)
      }
    }
  }

  private var baseQuery: SelectOf<Reminder, ReminderText> {
    let searchText = searchText
      .split(separator: " ")
      .map { #""\#($0.replacingOccurrences(of: #"""#, with: #""""#))""# }
      .joined(separator: " ")
    return Reminder
      .join(ReminderText.all) { $0.id.eq($1.reminderID) }
      .where {
        if !searchText.isEmpty {
          $1.match(searchText)
        }
      }
  }

  private func updateQuery() async {
    await withErrorReporting {
      if searchText.isEmpty {
        showCompletedInSearchResults = false
      }

      let baseQuery = baseQuery
      try await $completedCount.load(
        baseQuery
          .where { reminder, _ in reminder.isCompleted }
          .count(),
        animation: .default
      )
      try await $reminders.load(
        baseQuery
          .where { reminder, _ in
            if !showCompletedInSearchResults {
              !reminder.isCompleted
            }
          }
          .order { reminder, _ in
            (reminder.isCompleted, reminder.dueDate)
          }
          .join(RemindersList.all) { $0.remindersListID.eq($2.id) }
          .select {
            Row.Columns(
              isPastDue: $0.isPastDue,
              notes: $1.notes.snippet("**", "**", "...", 64).replace("\n", " "),
              reminder: $0,
              remindersList: $2,
              tags: $1.tags.highlight("**", "**"),
              title: $1.title.highlight("**", "**")
            )
          },
        animation: .default
      )
    }
  }

  @Selection
  struct Row: Identifiable {
    var id: Reminder.ID { reminder.id }
    let isPastDue: Bool
    let notes: String
    let reminder: Reminders.Reminder
    let remindersList: RemindersList
    let tags: String
    let title: String
  }
}

struct SearchRemindersView: View {
  let model: SearchRemindersModel

  init(model: SearchRemindersModel) {
    self.model = model
  }

  var body: some View {
    HStack {
      Text("\(model.completedCount) Completed")
        .monospacedDigit()
        .contentTransition(.numericText())
      if model.completedCount > 0 {
        Text("•")
        Menu {
          Text("Clear Completed Reminders")
          Button("Older Than 1 Month") {
            model.deleteCompletedReminders(monthsAgo: 1)
          }
          Button("Older Than 6 Months") {
            model.deleteCompletedReminders(monthsAgo: 6)
          }
          Button("Older Than 1 year") {
            model.deleteCompletedReminders(monthsAgo: 12)
          }
          Button("All Completed") {
            model.deleteCompletedReminders()
          }
        } label: {
          Text("Clear")
        }
        Spacer()
        Button(model.showCompletedInSearchResults ? "Hide" : "Show") {
          Task { await model.showCompletedButtonTapped() }
        }
      }
    }
    .buttonStyle(.borderless)

    ForEach(model.reminders) { reminder in
      ReminderRow(
        color: reminder.remindersList.color,
        isPastDue: reminder.isPastDue,
        notes: reminder.notes,
        reminder: reminder.reminder,
        remindersList: reminder.remindersList,
        showCompleted: model.showCompletedInSearchResults,
        tags: reminder.tags,
        title: reminder.title
      )
    }
  }
}

#Preview {
  @Previewable @State var searchText = "take"
  let _ = try! prepareDependencies {
    $0.defaultDatabase = try Reminders.appDatabase()
  }

  NavigationStack {
    List {
      if !searchText.isEmpty {
        SearchRemindersView(model: SearchRemindersModel())
      } else {
        Text(#"Tap "Search"..."#)
      }
    }
    .searchable(text: $searchText)
  }
}
