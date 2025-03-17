import Sharing
import SharingGRDB
import StructuredQueriesGRDB
import SwiftUI

struct RemindersListDetailView: View {
  @SharedReader(value: []) private var reminderStates: [ReminderState]
  @AppStorage private var ordering: Ordering
  @AppStorage private var showCompleted: Bool
  private let remindersList: RemindersList

  @State var isNewReminderSheetPresented = false

  @Dependency(\.defaultDatabase) private var database

  init(remindersList: RemindersList) {
    self.remindersList = remindersList
    _ordering = AppStorage(wrappedValue: .dueDate, "ordering_list_\(remindersList.id)")
    _showCompleted = AppStorage(wrappedValue: false, "show_completed_list_\(remindersList.id)")
  }

  var body: some View {
    List {
      ForEach(reminderStates) { reminderState in
        ReminderRow(
          isPastDue: reminderState.isPastDue,
          reminder: reminderState.reminder,
          remindersList: remindersList,
          tags: reminderState.tags
        )
      }
    }
    .task(id: [ordering, showCompleted] as [AnyHashable]) {
      await withErrorReporting {
        try await updateQuery()
      }
    }
    .navigationTitle(remindersList.name)
    .navigationBarTitleDisplayMode(.large)
    .sheet(isPresented: $isNewReminderSheetPresented) {
      NavigationStack {
        ReminderFormView(remindersList: remindersList)
      }
    }
    .toolbar {
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

  private func updateQuery() async throws {
    try await $reminderStates.load(remindersKey)
  }

  fileprivate var remindersKey: some SharedReaderKey<[ReminderState]> {
    .fetchAll(
      Reminder
        .where { $0.remindersListID == remindersList.id && (showCompleted || !$0.isCompleted) }
        .order {
          switch ordering {
          case .dueDate:
            ($0.isCompleted, $0.date)
          case .priority:
            ($0.isCompleted, $0.priority.desc(), $0.isFlagged.desc())
          case .title:
            ($0.isCompleted, $0.title)
          }
        }
        .withTags
        .select {
          ReminderState.Columns(
            reminder: $0,
            isPastDue: $0.isPastDue,
            commaSeparatedTags: $2.name.groupConcat()
          )
        },
      animation: .default
    )
  }

  @Selection
  fileprivate struct ReminderState: Decodable, Identifiable {
    var id: Reminder.ID { reminder.id }
    var reminder: Reminder
    var isPastDue: Bool
    var commaSeparatedTags: String?
    var tags: [String] {
      (commaSeparatedTags ?? "").split(separator: ",").map(String.init)
    }
  }
}

extension Reminder {
  static let withTags = group(by: \.id)
    .leftJoin(ReminderTag.all()) { $0.id.eq($1.reminderID) }
    .leftJoin(Tag.all()) { $1.tagID.eq($2.id) }
}

struct RemindersListDetailPreview: PreviewProvider {
  static var previews: some View {
    let remindersList = try! prepareDependencies {
      $0.defaultDatabase = try Reminders.appDatabase()
      return try $0.defaultDatabase.read { db in
        try RemindersList.all().fetchOne(db)!
      }
    }
    NavigationStack {
      RemindersListDetailView(remindersList: remindersList)
    }
  }
}
