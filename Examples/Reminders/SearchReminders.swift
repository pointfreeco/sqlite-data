import IssueReporting
import SQLiteData
import SwiftUI

@MainActor
@Observable
class SearchRemindersModel {
  var showCompletedInSearchResults = false {
    didSet {
      if oldValue != showCompletedInSearchResults {
        searchTask = Task { try await updateQuery(debounce: false) }
      }
    }
  }

  var searchText = "" {
    didSet {
      if oldValue != searchText {
        guard !searchText.hasSuffix("\t")
        else {
          searchTokens.append(Token(kind: .near, rawValue: String(searchText.dropLast())))
          searchText = ""
          return
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
          .where {
            $0.isCompleted
              && $0.id.in(
                baseQuery(searchText: searchText, searchTokens: searchTokens).select { $1.id }
              )
          }
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
            searchText: searchText,
            searchTokens: searchTokens,
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
    let searchText: String
    let searchTokens: [Token]
    let showCompletedInSearchResults: Bool
    func fetch(_ db: Database) throws -> Value {
      let baseQuery = baseQuery(searchText: searchText, searchTokens: searchTokens)
      return try Value(
        completedCount:
          baseQuery
          .where { $1.isCompleted }
          .count()
          .fetchOne(db) ?? 0,
        rows:
          baseQuery
          .where {
            if !showCompletedInSearchResults {
              !$1.isCompleted
            }
          }
          .order {
            ($1.isCompleted, $1.dueDate)
          }
          .join(RemindersList.all) { $1.remindersListID.eq($2.id) }
          .select {
            Row.Columns(
              isPastDue: $1.isPastDue,
              notes: $0.notes.snippet("**", "**", "...", 64).replace("\n", " "),
              reminder: $1,
              remindersList: $2,
              tags: $0.tags.highlight("**", "**"),
              title: $0.title.highlight("**", "**")
            )
          }
          .fetchAll(db)
      )
    }
  }

  nonisolated struct Token: Hashable, Identifiable {
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

nonisolated private func baseQuery(
  searchText: String,
  searchTokens: [SearchRemindersModel.Token]
) -> SelectOf<ReminderText, Reminder> {
  let searchText = searchText.quoted()

  return
    ReminderText
    .where {
      if !searchText.isEmpty {
        $0.match(searchText)
      }
    }
    .where {
      for token in searchTokens {
        switch token.kind {
        case .near:
          $0.match("NEAR(\(token.rawValue.quoted()))")
        case .tag:
          $0.tags.match(token.rawValue)
        }
      }
    }
    .join(Reminder.all) { $0.rowid.eq($1.rowid) }
}

extension String {
  nonisolated fileprivate func quoted() -> String {
    split(separator: " ")
      .map { #""\#($0.replacingOccurrences(of: #"""#, with: #""""#))""# }
      .joined(separator: " ")
  }
}
