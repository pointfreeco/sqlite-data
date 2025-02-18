import Dependencies
import GRDB
import Sharing
import SharingGRDB
import StructuredQueries
import SwiftUI

struct RemindersListsView: View {
  @SharedReader(.fetch(RemindersLists(), animation: .default)) private var lists
  @SharedReader(.fetch(Stats())) private var stats = Stats.Value()

  @State private var isAddListPresented = false
  @State private var searchText = ""

  @Dependency(\.defaultDatabase) private var database

  var body: some View {
    List {
      if searchText.isEmpty {
        Section {
          Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
              ReminderGridCell(
                color: .blue,
                count: stats.todayCount,
                iconName: "calendar.circle.fill",
                title: "Today"
              ) {}
              ReminderGridCell(
                color: .red,
                count: stats.scheduledCount,
                iconName: "calendar.circle.fill",
                title: "Scheduled"
              ) {}
            }
            GridRow {
              ReminderGridCell(
                color: .gray,
                count: stats.allCount,
                iconName: "tray.circle.fill",
                title: "All"
              ) {}
              ReminderGridCell(
                color: .orange,
                count: stats.flaggedCount,
                iconName: "flag.circle.fill",
                title: "Flagged"
              ) {}
            }
            GridRow {
              ReminderGridCell(
                color: .gray,
                count: stats.completedCount,
                iconName: "checkmark.circle.fill",
                title: "Completed"
              ) {}
            }
          }
        }
        .buttonStyle(.plain)
        
        Section {
          ForEach(lists, id: \.remindersList.id) { state in
            NavigationLink {
              RemindersListDetailView(remindersList: state.remindersList)
            } label: {
              RemindersListRow(
                reminderCount: state.reminderCount,
                remindersList: state.remindersList
              )
            }
          }
        } header: {
          Text("My lists")
            .font(.largeTitle)
            .bold()
            .foregroundStyle(.black)
        }
      } else {
        SearchRemindersView(searchText: searchText)
      }
    }
    // NB: This explicit view identity works around a bug with 'List' view state not getting reset.
    .id(searchText)
    .listStyle(.plain)
    .toolbar {
      Button("Add list") {
        isAddListPresented = true
      }
    }
    .sheet(isPresented: $isAddListPresented) {
      NavigationStack {
        RemindersListForm()
          .navigationTitle("New list")
      }
      .presentationDetents([.medium])
    }
    .sheet(isPresented: $isAddListPresented) {
      NavigationStack {
        RemindersListForm()
          .navigationTitle("New list")
      }
      .presentationDetents([.medium])
    }
    .searchable(text: $searchText)
  }

  struct RemindersLists: FetchKeyRequest {
    func fetch(_ db: Database) throws -> [Record] {
      try RemindersList
        .group(by: \.id)
        .join(Reminder.where { !$0.isCompleted }) { $0.id == $1.listID }
        .select { ($0, $1.id.count()) }
        .fetchAll(db)
        .map { Record(reminderCount: $1, remindersList: $0) }
    }
    // TODO: Fix @Selection to support queryfragment changes
    struct Record: Decodable, FetchableRecord {
      var reminderCount: Int
      var remindersList: RemindersList
    }
  }
  private struct Stats: FetchKeyRequest {
    func fetch(_ db: Database) throws -> Value {
      let todayCount = try Reminder.count()
        .where { .raw("date(\(bind: $0.date)) = date('now')") }
        .fetchOne(db) ?? 0
      let allCount = try Reminder.fetchCount(db)
      let scheduledCount = try Reminder.count()
        .where { .raw("date(\(bind: $0.date)) > date('now')") }
        .fetchOne(db) ?? 0
      let flaggedCount = try Reminder.where(\.isFlagged).count().fetchOne(db) ?? 0
      let completedCount = try Reminder.where(\.isCompleted).count().fetchOne(db) ?? 0
      return Value(
        allCount: allCount,
        completedCount: completedCount,
        flaggedCount: flaggedCount,
        scheduledCount: scheduledCount,
        todayCount: todayCount
      )
    }
    struct Value {
      var allCount = 0
      var completedCount = 0
      var flaggedCount = 0
      var scheduledCount = 0
      var todayCount = 0
    }
  }
}

private struct ReminderGridCell: View {
  let color: Color
  let count: Int
  let iconName: String
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .top) {
        VStack(alignment: .leading) {
          Image(systemName: iconName)
            .font(.largeTitle)
            .bold()
            .foregroundStyle(color)
          Text(title)
            .bold()
        }
        Spacer()
        Text("\(count)")
          .font(.largeTitle)
          .fontDesign(.rounded)
          .bold()
      }
      .padding()
      .background(.black.opacity(0.05))
      .cornerRadius(10)
    }
  }
}

#Preview {
  let _ = try! prepareDependencies {
    $0.defaultDatabase = try Reminders.appDatabase(inMemory: true)
  }
  NavigationStack {
    RemindersListsView()
  }
}
