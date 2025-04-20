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
        .leftJoin(Reminder.incomplete) { $0.id.eq($1.remindersListID) }
        .select {
          ReminderListState.Columns(
            remindersCount: $1.id.count(),
            remindersList: $0
          )
        },
      animation: .default
    )
  )
  private var remindersLists

  @SharedReader(
    .fetchAll(
      Tag
        .order(by: \.title)
        .withReminders
        .having { $2.count().gt(0) }
        .select { tag, _, _ in tag },
      animation: .default
    )
  )
  private var tags

  @SharedReader(
    .fetchOne(
      Reminder.select {
        Stats.Columns(
          allCount: $0.count(filter: !$0.isCompleted),
          flaggedCount: $0.count(filter: $0.isFlagged),
          scheduledCount: $0.count(filter: $0.isScheduled),
          todayCount: $0.count(filter: $0.isToday)
        )
      }
    )
  )
  private var stats = Stats()

  @State private var destination: Destination?
  @State private var remindersDetailType: RemindersListDetailView.DetailType?
  @State private var searchText = ""

  @Dependency(\.defaultDatabase) private var database

  @Selection
  fileprivate struct ReminderListState: Identifiable {
    var id: RemindersList.ID { remindersList.id }
    var remindersCount: Int
    var remindersList: RemindersList
  }

  @Selection
  fileprivate struct Stats {
    var allCount = 0
    var flaggedCount = 0
    var scheduledCount = 0
    var todayCount = 0
  }

  enum Destination: Int, Identifiable {
    case addList
    case newReminder

    var id: Int { rawValue }
  }

  var body: some View {
    List {
      if searchText.isEmpty {
        Section {
          Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
              ReminderGridCell(
                color: .blue,
                count: stats.todayCount,
                iconName: "calendar.circle.fill",
                title: "Today"
              ) {
                remindersDetailType = .today
              }
              ReminderGridCell(
                color: .red,
                count: stats.scheduledCount,
                iconName: "calendar.circle.fill",
                title: "Scheduled"
              ) {
                remindersDetailType = .scheduled
              }
            }
            GridRow {
              ReminderGridCell(
                color: .gray,
                count: stats.allCount,
                iconName: "tray.circle.fill",
                title: "All"
              ) {
                remindersDetailType = .all
              }
              ReminderGridCell(
                color: .orange,
                count: stats.flaggedCount,
                iconName: "flag.circle.fill",
                title: "Flagged"
              ) {
                remindersDetailType = .flagged
              }
            }
            GridRow {
              ReminderGridCell(
                color: .gray,
                count: nil,
                iconName: "checkmark.circle.fill",
                title: "Completed"
              ) {
                remindersDetailType = .completed
              }
            }
          }
          .buttonStyle(.plain)
          .listRowBackground(Color.clear)
          .padding([.leading, .trailing], -20)
        }

        Section {
          ForEach(remindersLists) { state in
            NavigationLink {
              RemindersListDetailView(detailType: .list(state.remindersList))
            } label: {
              RemindersListRow(
                remindersCount: state.remindersCount,
                remindersList: state.remindersList
              )
            }
          }
        } header: {
          Text("My Lists")
            .font(.system(.title2, design: .rounded, weight: .bold))
            .foregroundStyle(Color(.label))
            .textCase(nil)
            .padding(.top, -16)
            .padding([.leading, .trailing], 4)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

        Section {
          ForEach(tags) { tag in
            NavigationLink {
              RemindersListDetailView(detailType: .tags([tag]))
            } label: {
              TagRow(tag: tag)
            }
          }
        } header: {
          Text("Tags")
            .font(.system(.title2, design: .rounded, weight: .bold))
            .foregroundStyle(Color(.label))
            .textCase(nil)
            .padding(.top, -16)
            .padding([.leading, .trailing], 4)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
      } else {
        SearchRemindersView(searchText: searchText)
      }
    }
    // NB: This explicit view identity works around a bug with 'List' view state not getting reset.
    .id(searchText)
    .listStyle(.insetGrouped)
    .toolbar {
      ToolbarItem(placement: .bottomBar) {
        HStack {
          Button {
            destination = .newReminder
          } label: {
            HStack {
              Image(systemName: "plus.circle.fill")
              Text("New Reminder")
            }
            .bold()
            .font(.title3)
          }
          Spacer()
          Button {
            destination = .addList
          } label: {
            Text("Add List")
              .font(.title3)
          }
        }
      }
    }
    .sheet(item: $destination) { destination in
      switch destination {
      case .addList:
        NavigationStack {
          RemindersListForm()
            .navigationTitle("New List")
        }
        .presentationDetents([.medium])
      case .newReminder:
        if let remindersList = remindersLists.first?.remindersList {
          NavigationStack {
            ReminderFormView(remindersList: remindersList)
              .navigationTitle("New Reminder")
          }
        }
      }
    }
    .searchable(text: $searchText)
    .navigationDestination(item: $remindersDetailType) { detailType in
      RemindersListDetailView(detailType: detailType)
    }
  }
}

private struct ReminderGridCell: View {
  let color: Color
  let count: Int?
  let iconName: String
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 8) {
          Image(systemName: iconName)
            .font(.largeTitle)
            .bold()
            .foregroundStyle(color)
            .background(
              Color.white.clipShape(Circle()).padding(4)
            )
          Text(title)
            .font(.headline)
            .foregroundStyle(.gray)
            .bold()
            .padding(.leading, 4)
        }
        Spacer()
        if let count {
          Text("\(count)")
            .font(.largeTitle)
            .fontDesign(.rounded)
            .bold()
            .foregroundStyle(Color(.label))
        }
      }
      .padding(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
      .background(Color(.secondarySystemGroupedBackground))
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
