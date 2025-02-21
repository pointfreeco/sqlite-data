import IssueReporting
import SharingGRDB
import StructuredQueries
import SwiftUI

struct SearchRemindersView: View {
  @State.SharedReader(value: 0) var completedCount: Int
  @State.SharedReader(value: []) var reminders: [ReminderState]
  let searchText: String
  @State var showCompletedInSearchResults = false

  @Dependency(\.defaultDatabase) private var database

  init(searchText: String) {
    self.searchText = searchText
  }

  var body: some View {
    HStack {
      Text("\(completedCount) Completed")
        .monospacedDigit()
        .contentTransition(.numericText())
      if completedCount > 0 {
        Text("•")
        Menu {
          Text("Clear Completed Reminders")
          Button("Older Than 1 Month") { deleteCompletedReminders(monthsAgo: 1) }
          Button("Older Than 6 Months") { deleteCompletedReminders(monthsAgo: 6) }
          Button("Older Than 1 year") { deleteCompletedReminders(monthsAgo: 12) }
          Button("All Completed") { deleteCompletedReminders() }
        } label: {
          Text("Clear")
        }
        Spacer()
        if showCompletedInSearchResults {
          Button("Hide") {
            showCompletedInSearchResults = false
          }
        } else {
          Button("Show") {
            showCompletedInSearchResults = true
          }
        }
      }
    }
    .buttonStyle(.borderless)
    .task(id: [searchText, showCompletedInSearchResults] as [AnyHashable]) {
      await withErrorReporting {
        try await updateSearchQuery()
      }
    }

    ForEach(reminders) { reminder in
      ReminderRow(
        isPastDue: reminder.isPastDue,
        reminder: reminder.reminder,
        remindersList: reminder.remindersList,
        tags: reminder.tags
      )
    }
  }

  private func updateSearchQuery() async throws {
    if searchText.isEmpty {
      showCompletedInSearchResults = false
    }
    try await $completedCount.load(
      .fetchOne(
        Reminder.searching(searchText)
          .where(\.isCompleted)
          .count(),
        animation: .default
      )
    )
    try await $reminders.load(
      .fetchAll(
        Reminder.searching(searchText)
          .where { showCompletedInSearchResults || !$0.isCompleted }
          .order { ($0.isCompleted, $0.date) }
          .withTags
          .leftJoin(RemindersList.all()) { $0.listID == $3.id }
          .select {
            ReminderState.Columns(
              commaSeparatedTags: $2.name.groupConcat(),
              isPastDue: $0.isPastDue,
              reminder: $0,
              remindersList: $3
            )
          },
        animation: .default
      )
    )
  }

  private func deleteCompletedReminders(monthsAgo: Int? = nil) {
    withErrorReporting {
      try database.write { db in
        let baseQuery = Reminder
          .searching(searchText)
          .where(\.isCompleted)
        if let monthsAgo {
          try baseQuery
            .where { .raw("\($0.date) < date('now', '-\(monthsAgo) months") }
            .delete()
            .execute(db)
        } else {
          try baseQuery.delete().execute(db)
        }
      }
    }
  }

  @Selection
  struct ReminderState: Identifiable {
    var id: Reminder.ID { reminder.id }
    let commaSeparatedTags: String?
    var isPastDue: Bool
    let reminder: Reminders.Reminder
    let remindersList: RemindersList
    var tags: [String] {
      (commaSeparatedTags ?? "").split(separator: ",").map(String.init)
    }
  }
}

#Preview {
  @Previewable @State var searchText = "take"
  let _ = try! prepareDependencies {
    $0.defaultDatabase = try Reminders.appDatabase(inMemory: true)
  }

  NavigationStack {
    List {
      if !searchText.isEmpty {
        SearchRemindersView(searchText: searchText)
      } else {
        Text(#"Tap "Search"..."#)
      }
    }
    .searchable(text: $searchText)
  }
}
