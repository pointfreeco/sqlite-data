import CasePaths
import Sharing
import SharingGRDB
import StructuredQueriesGRDB
import SwiftUI

struct RemindersListDetailView: View {
  @SharedReader(value: []) private var reminderStates: [ReminderState]
  @AppStorage private var ordering: Ordering
  @AppStorage private var showCompleted: Bool

  let detailType: DetailType
  @State var isNewReminderSheetPresented = false

  @Dependency(\.defaultDatabase) private var database

  init(detailType: DetailType) {
    self.detailType = detailType
    _ordering = AppStorage(wrappedValue: .dueDate, "ordering_list_\(detailType.tag)")
    _showCompleted = AppStorage(
      wrappedValue: detailType != .completed,
      "show_completed_list_\(detailType.tag)"
    )
    _reminderStates = SharedReader(wrappedValue: [], remindersKey)
  }

  var body: some View {
    List {
      ForEach(reminderStates) { reminderState in
        ReminderRow(
          isPastDue: reminderState.isPastDue,
          reminder: reminderState.reminder,
          remindersList: reminderState.remindersList,
          tags: reminderState.tags
        )
      }
    }
    .task(id: [ordering, showCompleted] as [AnyHashable]) {
      await withErrorReporting {
        try await updateQuery()
      }
    }
    .navigationTitle(detailType.navigationTitle)
    .navigationBarTitleDisplayMode(.large)
    .sheet(isPresented: $isNewReminderSheetPresented) {
      if let remindersList = detailType.list {
        NavigationStack {
          ReminderFormView(remindersList: remindersList)
        }
      }
    }
    .toolbar {
      if detailType.is(\.list) {
        ToolbarItem(placement: .bottomBar) {
          HStack {
            Button {
              isNewReminderSheetPresented = true
            } label: {
              HStack {
                Image(systemName: "plus.circle.fill")
                Text("New reminder")
              }
              .bold()
              .font(.title3)
            }
            Spacer()
          }
        }
      }
      ToolbarItem(placement: .primaryAction) {
        Menu {
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
    case today
    var tag: String {
      switch self {
      case .all:
        "all"
      case .completed:
        "completed"
      case .flagged:
        "flagged"
      case .list(let list):
        "list_\(list.id)"
      case .scheduled:
        "scheduled"
      case .today:
        "today"
      }
    }
    var navigationTitle: String {
      switch self {
      case .all:
        "All"
      case .completed:
        "Completed"
      case .flagged:
        "Flagged"
      case .list(let list):
        list.name
      case .scheduled:
        "Scheduled"
      case .today:
        "Today"
      }
    }
  }

  private func updateQuery() async throws {
    try await $reminderStates.load(remindersKey)
  }

  fileprivate var remindersKey: some SharedReaderKey<[ReminderState]> {
    .fetchAll(
      Reminder
        .where {
          if !showCompleted {
            !$0.isCompleted
          }
        }
        .where {
          switch detailType {
          case .all: !$0.isCompleted
          case .completed: $0.isCompleted
          case .flagged: $0.isFlagged
          case .list(let list): $0.remindersListID.eq(list.id)
          case .scheduled: $0.isScheduled
          case .today: $0.isToday
          }
        }
        .order { $0.isCompleted }
        .order {
          switch ordering {
          case .dueDate:
            $0.date
          case .priority:
            ($0.priority.desc(), $0.isFlagged.desc())
          case .title:
            $0.title
          }
        }
        .withTags
        .join(RemindersList.all) { $0.remindersListID.eq($3.id) }
        .select {
          ReminderState.Columns(
            reminder: $0,
            remindersList: $3,
            isPastDue: $0.isPastDue,
            commaSeparatedTags: $2.name.groupConcat()
          )
        },
      animation: .default
    )
  }

  @Selection
  fileprivate struct ReminderState: Identifiable {
    var id: Reminder.ID { reminder.id }
    let reminder: Reminder
    let remindersList: RemindersList
    let isPastDue: Bool
    let commaSeparatedTags: String?
    var tags: [String] {
      (commaSeparatedTags ?? "").split(separator: ",").map(String.init)
    }
  }
}

extension Reminder {
  static let withTags = group(by: \.id)
    .leftJoin(ReminderTag.all) { $0.id.eq($1.reminderID) }
    .leftJoin(Tag.all) { $1.tagID.eq($2.id) }
}

struct RemindersListDetailPreview: PreviewProvider {
  static var previews: some View {
    let remindersList = try! prepareDependencies {
      $0.defaultDatabase = try Reminders.appDatabase()
      return try $0.defaultDatabase.read { db in
        try RemindersList.all.fetchOne(db)!
      }
    }
    NavigationStack {
      RemindersListDetailView(detailType: .list(remindersList))
    }
  }
}
