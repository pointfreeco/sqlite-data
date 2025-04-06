import IssueReporting
import SharingGRDB
import StructuredQueries
import SwiftUI

@MainActor
@Observable
class SearchRemindersModel {
  @ObservationIgnored
  @SharedReader(value: 0) var completedCount: Int
  @ObservationIgnored
  @SharedReader(value: []) var reminders: [ReminderState]

  var searchText: String
  var showCompletedInSearchResults: Bool

  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database

  init(
    searchText: String = "",
    showCompletedInSearchResults: Bool = false,
  ) {
    self.searchText = searchText
    self.showCompletedInSearchResults = showCompletedInSearchResults
  }

  func updateSearchQuery() async throws {
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
    try await $reminders.load(searchKey)
  }

  private var searchKey: some SharedReaderKey<[ReminderState]> {
    let query = Reminder.searching(searchText)
      .where { showCompletedInSearchResults || !$0.isCompleted }
      .order { ($0.isCompleted, $0.date) }
      .withTags
      .join(RemindersList.all) { $0.remindersListID.eq($3.id) }
      .select {
        ReminderState.Columns(
          commaSeparatedTags: $2.name.groupConcat(),
          isPastDue: $0.isPastDue,
          reminder: $0,
          remindersList: $3
        )
      }
    return .fetchAll(query, animation: .default)
  }

  func deleteButtonTapped(monthsAgo: Int? = nil) {
    withErrorReporting {
      try database.write { db in
        let baseQuery = Reminder
          .searching(searchText)
          .where(\.isCompleted)
        if let monthsAgo {
          try baseQuery
            .where { #sql("\($0.date) < date('now', '-\(raw: monthsAgo) months')") }
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

struct SearchRemindersView: View {
  let model: SearchRemindersModel

  var body: some View {
    HStack {
      Text("\(model.completedCount) Completed")
        .monospacedDigit()
        .contentTransition(.numericText())
      if model.completedCount > 0 {
        Text("•")
        Menu {
          Text("Clear Completed Reminders")
          Button("Older Than 1 Month") { model.deleteButtonTapped(monthsAgo: 1) }
          Button("Older Than 6 Months") { model.deleteButtonTapped(monthsAgo: 6) }
          Button("Older Than 1 year") { model.deleteButtonTapped(monthsAgo: 12) }
          Button("All Completed") { model.deleteButtonTapped() }
        } label: {
          Text("Clear")
        }
        Spacer()
        if model.showCompletedInSearchResults {
          Button("Hide") {
            model.showCompletedInSearchResults = false
          }
        } else {
          Button("Show") {
            model.showCompletedInSearchResults = true
          }
        }
      }
    }
    .buttonStyle(.borderless)
    .task(id: [model.searchText, model.showCompletedInSearchResults] as [AnyHashable]) {
      await withErrorReporting {
        try await model.updateSearchQuery()
      }
    }

    ForEach(model.reminders) { reminder in
      ReminderRow(
        isPastDue: reminder.isPastDue,
        reminder: reminder.reminder,
        remindersList: reminder.remindersList,
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
