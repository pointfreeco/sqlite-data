import IssueReporting
import SharingGRDB
import StructuredQueries
import SwiftUI

struct SearchRemindersView: View {
  @SharedReader(value: 0) var completedCount: Int
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
        Button(showCompletedInSearchResults ? "Hide" : "Show") {
          showCompletedInSearchResults.toggle()
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
        color: reminder.remindersList.color,
        isPastDue: reminder.isPastDue,
        notes: reminder.notes,
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
    let query = Reminder.where(\.isCompleted)
    try await $completedCount.load(
      .fetchOne(
        query
          .join(ReminderText.where { $0.match("\(searchText)*") }) { $0.id.eq($1.reminderID) }
          .count(),
        animation: .default
      )
    )
    try await $reminders.load(searchKey)
  }

  private var searchKey: some SharedReaderKey<[ReminderState]> {
    let query =
      Reminder
      .where { showCompletedInSearchResults || !$0.isCompleted }
      .order { ($0.isCompleted, $0.dueDate) }
      .withTags
      .join(RemindersList.all) { $0.remindersListID.eq($3.id) }
      .select {
        ReminderState.Columns(
          isPastDue: $0.isPastDue,
          notes: $0.notes.replace("\n", " "),
          reminder: $0,
          remindersList: $3,
          tags: #sql("\($2.name)").jsonGroupArray(filter: $2.name.isNot(nil))
        )
      }
      .join(ReminderText.where { $0.match("\(searchText)*") }) { $0.id.eq($1.reminderID) }
    return .fetchAll(query, animation: .default)
  }

  private func deleteCompletedReminders(monthsAgo: Int? = nil) {
    withErrorReporting {
      try database.write { db in
        try Reminder
          .where(\.isCompleted)
          .where {
            if let monthsAgo {
              #sql("\($0.dueDate) < date('now', '-\(raw: monthsAgo) months')")
            }
          }
          .where {
            $0.id.in(ReminderText.where { $0.match("\(searchText)*") }.select(\.reminderID))
          }
          .delete()
          .execute(db)
      }
    }
  }

  @Selection
  struct ReminderState: Identifiable {
    var id: Reminder.ID { reminder.id }
    let isPastDue: Bool
    let notes: String
    let reminder: Reminders.Reminder
    let remindersList: RemindersList
    @Column(as: JSONRepresentation<[String]>.self)
    let tags: [String]
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
        SearchRemindersView(searchText: searchText)
      } else {
        Text(#"Tap "Search"..."#)
      }
    }
    .searchable(text: $searchText)
  }
}
