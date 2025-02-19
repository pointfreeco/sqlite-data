import IssueReporting
import SharingGRDB
import StructuredQueries
import SwiftUI

struct SearchRemindersView: View {
  @State.SharedReader(value: SearchReminders.Value()) var searchReminders

  let searchText: String
  @State var showCompletedInSearchResults = false

  @Dependency(\.defaultDatabase) private var database

  init(searchText: String) {
    self.searchText = searchText
    $searchReminders = SharedReader(
      wrappedValue: searchReminders,
      .fetch(
        SearchReminders(
          showCompletedInSearchResults: showCompletedInSearchResults,
          searchText: searchText
        ),
        animation: .default
      )
    )
  }

  var body: some View {
    HStack {
      Text("\(searchReminders.completedCount) Completed")
        .monospacedDigit()
        .contentTransition(.numericText())
      if searchReminders.completedCount > 0 {
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

    ForEach(searchReminders.reminders, id: \.reminder.id) { reminder in
      ReminderRow(
        isPastDue: reminder.isPastDue,
        reminder: reminder.reminder,
        remindersList: reminder.remindersList,
        tags: (reminder.commaSeparatedTags ?? "").split(separator: ",").map(String.init)
      )
    }
  }

  private func updateSearchQuery() async throws {
    if searchText.isEmpty {
      showCompletedInSearchResults = false
    }
    try await $searchReminders.load(
      .fetch(
        SearchReminders(
          showCompletedInSearchResults: showCompletedInSearchResults,
          searchText: searchText
        ),
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
          _ = try baseQuery
            .where { .raw("\($0.date) < date('now', '-\(monthsAgo) months") }
            .delete()
            .execute(db)
        } else {
          _ = try baseQuery
            .delete()
            .execute(db)
        }
      }
    }
  }

  struct SearchReminders: FetchKeyRequest {
    let showCompletedInSearchResults: Bool
    let searchText: String

    func fetch(_ db: Database) throws -> Value {
      try Value(
        completedCount: Reminder.searching(searchText)
          .where(\.isCompleted)
          .count()
          .fetchOne(db) ?? 0,

        reminders: Reminder.searching(searchText)
          .order { ($0.isCompleted, $0.date) }
          .withTags(showCompleted: showCompletedInSearchResults)
          .leftJoin(RemindersList.all()) { $0.listID == $3.id }
          .select {
            Value.Reminder.Columns(
              isPastDue: $0.isPastDue,
              reminder: $0,
              remindersList: $3,
              commaSeparatedTags: $2.name.groupConcat()
            )
          }
          .fetchAll(db)
      )
    }
    struct Value {
      var completedCount = 0
      var reminders: [Reminder] = []
      @Selection
      struct Reminder {
        var isPastDue: Bool
        let reminder: Reminders.Reminder
        let remindersList: RemindersList
        let commaSeparatedTags: String?
      }
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
