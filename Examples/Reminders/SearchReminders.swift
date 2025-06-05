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
          .searching(searchText)
          .where(\.isCompleted)
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

  private func updateQuery() async {
    await withErrorReporting {
      if searchText.isEmpty {
        showCompletedInSearchResults = false
      }
      try await $completedCount.load(
        Reminder.searching(searchText)
          .where(\.isCompleted)
          .count(),
        animation: .default
      )
      try await $reminders.load(
        Reminder
          .searching(searchText)
          .where {
            if !showCompletedInSearchResults {
              !$0.isCompleted
            }
          }
          .order { ($0.isCompleted, $0.dueDate) }
          .withTags
          .join(RemindersList.all) { $0.remindersListID.eq($3.id) }
          .select {
            Row.Columns(
              isPastDue: $0.isPastDue,
              notes: $0.inlineNotes,
              reminder: $0,
              remindersList: $3,
              tags: #sql("\($2.jsonNames)")
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
    @Column(as: [String].JSONRepresentation.self)
    let tags: [String]
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
        tags: reminder.tags
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
