import CasePaths
import SharingGRDB
import SwiftUI

struct RemindersListDetailView: View {
  @FetchAll private var reminderStates: [ReminderState]
  @AppStorage private var ordering: Ordering
  @AppStorage private var showCompleted: Bool

  let detailType: DetailType
  @State var isNewReminderSheetPresented = false
  @State var isNavigationTitleVisible = false
  @State var navigationTitleHeight: CGFloat = 36

  @Dependency(\.defaultDatabase) private var database

  init(detailType: DetailType) {
    self.detailType = detailType
    _ordering = AppStorage(wrappedValue: .dueDate, "ordering_list_\(detailType.id)")
    _showCompleted = AppStorage(
      wrappedValue: detailType == .completed,
      "show_completed_list_\(detailType.id)"
    )
    _reminderStates = FetchAll(remindersQuery, animation: .default)
  }

  var body: some View {
    List {
      VStack(alignment: .leading) {
        GeometryReader { proxy in
          Text(detailType.navigationTitle)
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(detailType.color)
            .onAppear { navigationTitleHeight = proxy.size.height }
        }
      }
      .listRowSeparator(.hidden)
      ForEach(reminderStates) { reminderState in
        ReminderRow(
          color: detailType.color,
          isPastDue: reminderState.isPastDue,
          notes: reminderState.notes,
          reminder: reminderState.reminder,
          remindersList: reminderState.remindersList,
          showCompleted: showCompleted,
          tags: reminderState.tags
        )
      }
    }
    .onScrollGeometryChange(for: Bool.self) { geometry in
      geometry.contentOffset.y + geometry.contentInsets.top > navigationTitleHeight
    } action: {
      isNavigationTitleVisible = $1
    }
    .listStyle(.plain)
    .sheet(isPresented: $isNewReminderSheetPresented) {
      if let remindersList = detailType.list {
        NavigationStack {
          ReminderFormView(remindersList: remindersList)
            .navigationTitle("New Reminder")
        }
      }
    }
    .task(id: [ordering, showCompleted] as [AnyHashable]) {
      await withErrorReporting {
        try await updateQuery()
      }
    }
    .toolbar {
      ToolbarItem(placement: .principal) {
        Text(detailType.navigationTitle)
          .font(.headline)
          .opacity(isNavigationTitleVisible ? 1 : 0)
          .animation(.default.speed(2), value: isNavigationTitleVisible)
      }
    }
    .toolbarTitleDisplayMode(.inline)
    .toolbar {
      if detailType.is(\.list) {
        ToolbarItem(placement: .bottomBar) {
          HStack {
            Button {
              isNewReminderSheetPresented = true
            } label: {
              HStack {
                Image(systemName: "plus.circle.fill")
                Text("New Reminder")
              }
              .bold()
              .font(.title3)
            }
            Spacer()
          }
          .tint(detailType.color)
        }
      }
      ToolbarItem(placement: .primaryAction) {
        Menu {
          Group {
            Menu {
              ForEach(Ordering.allCases, id: \.self) { ordering in
                Button {
                  self.ordering = ordering
                } label: {
                  Text(ordering.rawValue)
                  ordering.icon
                }
              }
            } label: {
              Text("Sort By")
              Text(ordering.rawValue)
              Image(systemName: "arrow.up.arrow.down")
            }
            Button {
              showCompleted.toggle()
            } label: {
              Text(showCompleted ? "Hide Completed" : "Show Completed")
              Image(systemName: showCompleted ? "eye.slash.fill" : "eye")
            }
          }
          .tint(detailType.color)
        } label: {
          Image(systemName: "ellipsis.circle")
        }
      }
    }
  }

  private enum Ordering: String, CaseIterable {
    case dueDate = "Due Date"
    case priority = "Priority"
    case title = "Title"
    var icon: Image {
      switch self {
      case .dueDate: Image(systemName: "calendar")
      case .priority: Image(systemName: "chart.bar.fill")
      case .title: Image(systemName: "textformat.characters")
      }
    }
  }

  @CasePathable
  @dynamicMemberLookup
  enum DetailType: Hashable {
    case all
    case completed
    case flagged
    case list(RemindersList)
    case scheduled
    case tags([Tag])
    case today
  }

  private func updateQuery() async throws {
    try await $reminderStates.load(remindersQuery)
  }

  fileprivate var remindersQuery: some StructuredQueriesCore.Statement<ReminderState> {
    let query =
      Reminder
      .where {
        if !showCompleted {
          !$0.isCompleted
        }
      }
      .order { $0.isCompleted }
      .order {
        switch ordering {
        case .dueDate: $0.dueDate
        case .priority: ($0.priority.desc(), $0.isFlagged.desc())
        case .title: $0.title
        }
      }
      .withTags
      .where { reminder, _, tag in
        switch detailType {
        case .all: !reminder.isCompleted
        case .completed: reminder.isCompleted
        case .flagged: reminder.isFlagged
        case .list(let list): reminder.remindersListID.eq(list.id)
        case .scheduled: reminder.isScheduled
        case .tags(let tags): tag.id.ifnull(0).in(tags.map(\.id))
        case .today: reminder.isToday
        }
      }
      .join(RemindersList.all) { $0.remindersListID.eq($3.id) }
      .select {
        ReminderState.Columns(
          reminder: $0,
          remindersList: $3,
          isPastDue: $0.isPastDue,
          notes: $0.inlineNotes.substr(0, 200),
          tags: #sql("\($2.jsonNames)")
        )
      }
    return query
  }

  @Selection
  fileprivate struct ReminderState: Identifiable {
    var id: Reminder.ID { reminder.id }
    let reminder: Reminder
    let remindersList: RemindersList
    let isPastDue: Bool
    let notes: String
    @Column(as: JSONRepresentation<[String]>.self)
    let tags: [String]
  }
}

extension RemindersListDetailView.DetailType {
  fileprivate var id: String {
    switch self {
    case .all: "all"
    case .completed: "completed"
    case .flagged: "flagged"
    case .list(let list): "list_\(list.id)"
    case .scheduled: "scheduled"
    case .tags: "tags"
    case .today: "today"
    }
  }
  fileprivate var navigationTitle: String {
    switch self {
    case .all: "All"
    case .completed: "Completed"
    case .flagged: "Flagged"
    case .list(let list): list.title
    case .scheduled: "Scheduled"
    case .tags(let tags):
      switch tags.count {
      case 0: "Tags"
      case 1: "#\(tags[0].title)"
      default: "\(tags.count) tags"
      }
    case .today: "Today"
    }
  }
  fileprivate var color: Color {
    switch self {
    case .all: .black
    case .completed: .gray
    case .flagged: .orange
    case .list(let list): list.color
    case .scheduled: .red
    case .tags: .blue
    case .today: .blue
    }
  }
}

struct RemindersListDetailPreview: PreviewProvider {
  static var previews: some View {
    let (remindersList, tag) = try! prepareDependencies {
      $0.defaultDatabase = try Reminders.appDatabase()
      return try $0.defaultDatabase.read { db in
        (
          try RemindersList.all.fetchOne(db)!,
          try Tag.all.fetchOne(db)!
        )
      }
    }
    let detailTypes: [RemindersListDetailView.DetailType] = [
      .all,
      .list(remindersList),
      .tags([tag]),
    ]
    ForEach(detailTypes, id: \.self) { detailType in
      NavigationStack {
        RemindersListDetailView(detailType: detailType)
      }
      .previewDisplayName(detailType.navigationTitle)
    }
  }
}
