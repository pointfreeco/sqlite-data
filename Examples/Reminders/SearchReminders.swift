import IssueReporting
import SharingGRDB
import SwiftUI

@MainActor
@Observable
class SearchRemindersModel {
  var showCompletedInSearchResults = false {
    didSet {
      searchTask = Task { try await updateQuery(debounce: false) }
    }
  }

  var searchText = "" {
    didSet {
      if oldValue != searchText {
        if searchText.hasSuffix("\t") {
          searchTokens.append(Token(kind: .near, rawValue: String(searchText.dropLast())))
          searchText = ""
        }

        searchTask = Task { try await updateQuery() }
      }
    }
  }

  var searchTokens: [Token] = [] {
    didSet {
      if oldValue != searchTokens {
        searchTask = Task { try await updateQuery() }
      }
    }
  }

  var isSearching: Bool {
    !searchText.isEmpty || !searchTokens.isEmpty
  }

  var searchTask: Task<Void, any Error>? {
    willSet {
      searchTask?.cancel()
    }
  }

  @ObservationIgnored @Dependency(\.continuousClock) private var clock

  @ObservationIgnored @Dependency(\.defaultDatabase) private var database

  @ObservationIgnored @Fetch var searchResults = SearchRequest.Value()

  @ObservationIgnored @FetchAll(Tag.none) var tags

  func showCompletedButtonTapped() async throws {
    showCompletedInSearchResults.toggle()
    try await updateQuery()
  }

  func tagButtonTapped(_ tag: Tag) {
    guard !searchText.isEmpty else { return }
    searchTokens.append(Token(kind: .tag, rawValue: tag.title))
    searchText = ""
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
    let searchText =
      searchText
      .split(separator: " ")
      .map { #""\#($0.replacingOccurrences(of: #"""#, with: #""""#))""# }
      .joined(separator: " ")
    return
      Reminder
      .join(ReminderText.all) { $0.id.eq($1.reminderID) }
      .where {
        if !searchText.isEmpty {
          $1.match(searchText)
        }
      }
      .where { _, reminderText in
        for token in searchTokens {
          switch token.kind {
          case .near:
            reminderText.match("NEAR(\(token.rawValue))")
          case .tag:
            reminderText.tags.match(token.rawValue)
          }
        }
      }
  }

  private func updateQuery(debounce: Bool = true) async throws {
    if debounce {
      try await clock.sleep(for: .seconds(0.3))
    }
    await withErrorReporting {
      if !isSearching {
        showCompletedInSearchResults = false
      }

      if searchText.hasPrefix("#") {
        let existingTags = searchTokens.compactMap { $0.kind == .tag ? $0.rawValue : nil }
        try await $tags.load(
          Tag
            .where { $0.title.hasPrefix(searchText.dropFirst()) && !$0.title.in(existingTags) }
            .order(by: \.title)
        )
      } else {
        try await $searchResults.load(
          SearchRequest(
            baseQuery: baseQuery,
            showCompletedInSearchResults: showCompletedInSearchResults
          ),
          animation: .default
        )
      }
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

  struct SearchRequest: FetchKeyRequest {
    struct Value {
      var completedCount = 0
      var rows: [Row] = []
    }
    let baseQuery: SelectOf<Reminder, ReminderText>
    let showCompletedInSearchResults: Bool
    func fetch(_ db: Database) throws -> Value {
      try Value(
        completedCount:
          baseQuery
          .where { reminder, _ in reminder.isCompleted }
          .count()
          .fetchOne(db) ?? 0,
        rows:
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
          }
          .fetchAll(db)
      )
    }
  }

  struct Token: Hashable, Identifiable {
    enum Kind {
      case near
      case tag
    }

    var kind: Kind
    var rawValue = ""

    var id: Self { self }
  }
}

struct SearchRemindersView: View {
  let model: SearchRemindersModel

  init(model: SearchRemindersModel) {
    self.model = model
  }

  var body: some View {
    if model.searchText.hasPrefix("#"), !model.tags.isEmpty {
      Section {
        ScrollView(.horizontal) {
          HStack {
            ForEach(model.tags) { tag in
              Button("#\(tag.title)") {
                model.tagButtonTapped(tag)
              }
            }
          }
        }
        .scrollIndicators(.hidden)
      }
    }

    HStack {
      Text("\(model.searchResults.completedCount) Completed")
        .monospacedDigit()
        .contentTransition(.numericText())
      if model.searchResults.completedCount > 0 {
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
          Task { try await model.showCompletedButtonTapped() }
        }
      }
    }
    .buttonStyle(.borderless)

    ForEach(model.searchResults.rows) { row in
      ReminderRow(
        color: row.remindersList.color,
        isPastDue: row.isPastDue,
        notes: row.notes,
        reminder: row.reminder,
        remindersList: row.remindersList,
        showCompleted: model.showCompletedInSearchResults,
        tags: row.tags,
        title: row.title
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
