import CloudKit
import SQLiteData
import SwiftUI
import SwiftUINavigation
import TipKit

@MainActor
@Observable
class RemindersListsModel {
  @ObservationIgnored
  @FetchAll(
    RemindersList
      .group(by: \.id)
      .order(by: \.position)
      .leftJoin(Reminder.all) { $0.id.eq($1.remindersListID) && !$1.isCompleted }
      .leftJoin(SyncMetadata.all) { $0.syncMetadataID.eq($2.id) }
      .select {
        ReminderListState.Columns(
          remindersCount: $1.id.count(),
          remindersList: $0,
          share: $2.share
        )
      },
    animation: .default
  )
  var remindersLists

  @ObservationIgnored
  @FetchAll(
    Tag
      .order(by: \.title)
      .withReminders
      .having { $2.count().gt(0) }
      .select { tag, _, _ in tag },
    animation: .default
  )
  var tags

  @ObservationIgnored
  @FetchOne(
    Reminder.select {
      Stats.Columns(
        allCount: $0.count(filter: !$0.isCompleted),
        flaggedCount: $0.count(filter: $0.isFlagged && !$0.isCompleted),
        scheduledCount: $0.count(filter: $0.isScheduled),
        todayCount: $0.count(filter: $0.isToday)
      )
    }
  )
  var stats = Stats()

  var destination: Destination?
  var searchRemindersModel = SearchRemindersModel()
  var seedDatabaseTip: SeedDatabaseTip?

  @ObservationIgnored
  @Dependency(\.defaultDatabase) private var database

  func statTapped(_ detailType: RemindersDetailModel.DetailType) {
    destination = .detail(RemindersDetailModel(detailType: detailType))
  }

  func remindersListTapped(remindersList: RemindersList) {
    destination = .detail(
      RemindersDetailModel(
        detailType: .remindersList(
          remindersList
        )
      )
    )
  }

  func tagButtonTapped(tag: Tag) {
    destination = .detail(
      RemindersDetailModel(
        detailType: .tags([tag])
      )
    )
  }

  func deleteTags(atOffsets offsets: IndexSet) {
    withErrorReporting {
      let tagTitles = offsets.map { tags[$0].title }
      try database.write { db in
        try Tag
          .where { $0.title.in(tagTitles) }
          .delete()
          .execute(db)
      }
    }
  }

  func onAppear() {
    withErrorReporting {
      try Tips.configure()
    }
    if remindersLists.isEmpty {
      seedDatabaseTip = SeedDatabaseTip()
    }
  }

  func newReminderButtonTapped() {
    guard let remindersList = remindersLists.first?.remindersList
    else {
      reportIssue("There must be at least one list.")
      return
    }
    destination = .reminderForm(
      Reminder.Draft(remindersListID: remindersList.id),
      remindersList: remindersList
    )
  }

  func addListButtonTapped() {
    destination = .remindersListForm(RemindersList.Draft())
  }

  func listDetailsButtonTapped(remindersList: RemindersList) {
    destination = .remindersListForm(RemindersList.Draft(remindersList))
  }

  func move(from source: IndexSet, to destination: Int) {
    withErrorReporting {
      try database.write { db in
        var ids = remindersLists.map(\.remindersList.id)
        ids.move(fromOffsets: source, toOffset: destination)
        try RemindersList
          .where { $0.id.in(ids) }
          .update {
            let ids = Array(ids.enumerated())
            let (first, rest) = (ids.first!, ids.dropFirst())
            $0.position =
              rest
              .reduce(Case($0.id).when(first.element, then: first.offset)) { cases, id in
                cases.when(id.element, then: id.offset)
              }
              .else($0.position)
          }
          .execute(db)
      }
    }
  }

  #if DEBUG
    func seedDatabaseButtonTapped() {
      withErrorReporting {
        try database.write { db in
          try db.seedSampleData()
        }
      }
    }
  #endif

  @CasePathable
  enum Destination {
    case detail(RemindersDetailModel)
    case reminderForm(Reminder.Draft, remindersList: RemindersList)
    case remindersListForm(RemindersList.Draft)
  }

  @Selection
  struct ReminderListState: Identifiable {
    var id: RemindersList.ID { remindersList.id }
    var remindersCount: Int
    var remindersList: RemindersList
    @Column(as: CKShare?.SystemFieldsRepresentation.self)
    var share: CKShare?
  }

  @Selection
  struct Stats {
    var allCount = 0
    var flaggedCount = 0
    var scheduledCount = 0
    var todayCount = 0
  }

  struct SeedDatabaseTip: Tip {
    var title: Text {
      Text("Seed Sample Data")
    }
    var message: Text? {
      Text("Tap here to quickly populate the app with test data.")
    }
    var image: Image? {
      Image(systemName: "leaf")
    }
  }
}

struct RemindersListsView: View {
  @Bindable var model: RemindersListsModel
  @Dependency(\.defaultSyncEngine) var syncEngine

  var body: some View {
    List {
      if model.searchRemindersModel.isSearching {
        SearchRemindersView(model: model.searchRemindersModel)
      } else {
        Section {
          Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
              ReminderGridCell(
                color: .blue,
                count: model.stats.todayCount,
                iconName: "calendar.circle.fill",
                title: "Today"
              ) {
                model.statTapped(.today)
              }
              ReminderGridCell(
                color: .red,
                count: model.stats.scheduledCount,
                iconName: "calendar.circle.fill",
                title: "Scheduled"
              ) {
                model.statTapped(.scheduled)
              }
            }
            GridRow {
              ReminderGridCell(
                color: .gray,
                count: model.stats.allCount,
                iconName: "tray.circle.fill",
                title: "All"
              ) {
                model.statTapped(.all)
              }
              ReminderGridCell(
                color: .orange,
                count: model.stats.flaggedCount,
                iconName: "flag.circle.fill",
                title: "Flagged"
              ) {
                model.statTapped(.flagged)
              }
            }
            GridRow {
              ReminderGridCell(
                color: .gray,
                count: nil,
                iconName: "checkmark.circle.fill",
                title: "Completed"
              ) {
                model.statTapped(.completed)
              }
            }
          }
          .buttonStyle(.plain)
          .listRowBackground(Color.clear)
          .padding([.leading, .trailing], -20)
        }

        Section {
          ForEach(model.remindersLists) { state in
            Button {
              model.remindersListTapped(remindersList: state.remindersList)
            } label: {
              RemindersListRow(
                remindersCount: state.remindersCount,
                remindersList: state.remindersList,
                share: state.share
              )
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.primary)
          }
          .onMove(perform: model.move(from:to:))
        } header: {
          HStack {
            Text("My Lists")
            if syncEngine.isSynchronizing {
              ProgressView().id(UUID())
            }
          }
          .font(.system(.title2, design: .rounded, weight: .bold))
          .foregroundStyle(Color(.label))
          .textCase(nil)
          .padding(.top, -16)
          .padding([.leading, .trailing], 4)
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

        Section {
          ForEach(model.tags) { tag in
            Button {
              model.tagButtonTapped(tag: tag)
            } label: {
              TagRow(tag: tag)
            }
            .foregroundStyle(.primary)
          }
          .onDelete { offsets in
            model.deleteTags(atOffsets: offsets)
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
      }
    }
    .refreshable {
      await withErrorReporting {
        try await syncEngine.syncChanges()
      }
    }
    .onAppear {
      model.onAppear()
    }
    .listStyle(.insetGrouped)
    .toolbar {
      #if DEBUG
        ToolbarItem(placement: .automatic) {
          Menu {
            Button {
              model.seedDatabaseButtonTapped()
            } label: {
              Text("Seed data")
              Image(systemName: "leaf")
            }
            Button {
              if syncEngine.isRunning {
                syncEngine.stop()
              } else {
                Task {
                  await withErrorReporting {
                    try await syncEngine.start()
                  }
                }
              }
            } label: {
              Text("\(syncEngine.isRunning ? "Stop" : "Start") synchronizing")
              Image(systemName: syncEngine.isRunning ? "stop" : "play")
            }
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .popoverTip(model.seedDatabaseTip)
        }
      #endif
      ToolbarItem(placement: .bottomBar) {
        HStack {
          Button {
            model.newReminderButtonTapped()
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
            model.addListButtonTapped()
          } label: {
            Text("Add List")
              .font(.title3)
          }
        }
      }
    }
    .sheet(item: $model.destination.reminderForm, id: \.0.id) { reminder, remindersList in
      NavigationStack {
        ReminderFormView(reminder: reminder, remindersList: remindersList)
          .navigationTitle("New Reminder")
      }
    }
    .sheet(item: $model.destination.remindersListForm) { remindersList in
      NavigationStack {
        RemindersListForm(remindersList: remindersList)
          .navigationTitle("New List")
      }
      .presentationDetents([.medium])
    }
    .searchable(
      text: $model.searchRemindersModel.searchText,
      tokens: $model.searchRemindersModel.searchTokens
    ) { token in
      switch token.kind {
      case .near:
        Text(token.rawValue)
      case .tag:
        Text("#\(token.rawValue)")
      }
    }
    .navigationDestination(item: $model.destination.detail) { detailModel in
      RemindersDetailView(model: detailModel)
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
    RemindersListsView(model: RemindersListsModel())
  }
}
