import Dependencies
import GRDB
import Sharing
import SharingGRDB
import StructuredQueries
import SwiftUI

struct RemindersListsView: View {
  @SharedReader(
    .fetchAll(
    RemindersList
      .group(by: \.id)
      .leftJoin(Reminder.all()) { $0.id.eq($1.remindersListID) }
      .select {
        ReminderListState.Columns(
          reminderCount: #sql("total(NOT \($1.isCompleted))"),
          remindersList: $0
        )
      },
      animation: .default
    )
  )
  private var remindersLists
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
          ForEach(remindersLists) { state in
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

  @Selection
  fileprivate struct ReminderListState: Identifiable {
    var id: RemindersList.ID { remindersList.id }
    var reminderCount: Int
    var remindersList: RemindersList
  }
  fileprivate struct Stats: FetchKeyRequest {
    func fetch(_ db: Database) throws -> Value {
      try Value(
        allCount: Reminder.count().fetchOne(db) ?? 0,
        completedCount: Reminder.where(\.isCompleted).count().fetchOne(db) ?? 0,
        flaggedCount: Reminder.where(\.isFlagged).count().fetchOne(db) ?? 0,
        scheduledCount: Reminder.count()
          .where { #sql("date(\($0.date)) > date('now')") }
          .fetchOne(db) ?? 0,
        todayCount: Reminder.count()
          .where { #sql("date(\($0.date)) = date('now')") }
          .fetchOne(db) ?? 0
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
    $0.defaultDatabase = try Reminders.appDatabase()
  }
  NavigationStack {
    RemindersListsView()
  }
}
