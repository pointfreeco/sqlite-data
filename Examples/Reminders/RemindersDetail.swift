import CasePaths
import CloudKit
import SQLiteData
import Sharing
import SwiftUI
import SwiftUINavigation

@MainActor
@Observable
class RemindersDetailModel: HashableObject {
  @ObservationIgnored @FetchAll var reminderRows: [Row]
  @ObservationIgnored @FetchOne var coverImageData: Data?
  @ObservationIgnored @Shared var ordering: Ordering
  @ObservationIgnored @Shared var showCompleted: Bool

  let detailType: DetailType
  var isNewReminderSheetPresented = false
  var sharedRecord: SharedRecord?

  @ObservationIgnored @Dependency(\.defaultDatabase) private var database
  @ObservationIgnored @Dependency(\.defaultSyncEngine) private var syncEngine

  init(detailType: DetailType) {
    self.detailType = detailType
    _ordering = Shared(wrappedValue: .dueDate, .appStorage("ordering_list_\(detailType.id)"))
    _showCompleted = Shared(
      wrappedValue: detailType == .completed,
      .appStorage("show_completed_list_\(detailType.id)")
    )
    _reminderRows = FetchAll(remindersQuery, animation: .default)
    if let remindersListID = detailType.remindersList?.id {
      _coverImageData = FetchOne(
        RemindersListAsset
          .where { $0.remindersListID.eq(remindersListID) }
          .select(\.coverImage),
        animation: .default
      )
    }
  }

  func orderingButtonTapped(_ ordering: Ordering) async {
    $ordering.withLock { $0 = ordering }
    await updateQuery()
  }

  func showCompletedButtonTapped() async {
    $showCompleted.withLock { $0.toggle() }
    await updateQuery()
  }

  func move(from source: IndexSet, to destination: Int) async {
    withErrorReporting {
      try database.write { db in
        var ids = reminderRows.map(\.reminder.id)
        ids.move(fromOffsets: source, toOffset: destination)
        try Reminder
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
    $ordering.withLock { $0 = .manual }
    await updateQuery()
  }

  func shareButtonTapped() async {
    guard let remindersList = detailType.remindersList
    else { return }
    sharedRecord = await withErrorReporting {
      try await syncEngine.share(record: remindersList) { share in
        share[CKShare.SystemFieldKey.title] = remindersList.title
      }
    }
  }

  private func updateQuery() async {
    await withErrorReporting {
      try await $reminderRows.load(remindersQuery, animation: .default)
    }
  }

  private var remindersQuery: some StructuredQueriesCore.Statement<Row> {
    Reminder
      .where {
        if !showCompleted {
          $0.status.neq(Reminder.Status.completed)
        }
      }
      .order {
        if showCompleted {
          $0.isCompleted
        } else {
          $0.status.eq(Reminder.Status.completed)
        }
      }
      .order {
        switch ordering {
        case .dueDate: $0.dueDate.asc(nulls: .last)
        case .manual: $0.position
        case .priority: ($0.priority.desc(), $0.isFlagged.desc())
        case .title: $0.title
        }
      }
      .withTags
      .where { reminder, _, tag in
        switch detailType {
        case .all: true
        case .completed: reminder.isCompleted
        case .flagged: reminder.isFlagged
        case .remindersList(let list): reminder.remindersListID.eq(list.id)
        case .scheduled: reminder.isScheduled
        case .tags(let tags): tag.primaryKey.ifnull("").in(tags.map(\.primaryKey))
        case .today: reminder.isToday
        }
      }
      .join(RemindersList.all) { $0.remindersListID.eq($3.id) }
      .join(ReminderText.all) { $0.rowid.eq($4.rowid) }
      .select {
        Row.Columns(
          reminder: $0,
          remindersList: $3,
          isPastDue: $0.isPastDue,
          notes: $4.notes.substr(0, 200),
          tags: $4.tags
        )
      }
  }

  enum Ordering: String, CaseIterable {
    case dueDate = "Due Date"
    case manual = "Manual"
    case priority = "Priority"
    case title = "Title"
    var icon: Image {
      switch self {
      case .dueDate: Image(systemName: "calendar")
      case .manual: Image(systemName: "hand.draw")
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
    case remindersList(RemindersList)
    case scheduled
    case tags([Tag])
    case today
  }

  @Selection
  struct Row: Identifiable {
    var id: Reminder.ID { reminder.id }
    let reminder: Reminder
    let remindersList: RemindersList
    let isPastDue: Bool
    let notes: String
    let tags: String
  }
}

struct RemindersDetailView: View {
  @Bindable var model: RemindersDetailModel

  @State var isNavigationTitleVisible = false
  @State var navigationTitleHeight: CGFloat = 36

  var body: some View {
    List {
      header
      ForEach(model.reminderRows) { row in
        ReminderRow(
          color: model.detailType.color,
          isPastDue: row.isPastDue,
          notes: row.notes,
          reminder: row.reminder,
          remindersList: row.remindersList,
          showCompleted: model.showCompleted,
          tags: row.tags
        )
      }
      .onMove { source, destination in
        Task { await model.move(from: source, to: destination) }
      }
    }
    .onScrollGeometryChange(for: Bool.self) { geometry in
      geometry.contentOffset.y + geometry.contentInsets.top > navigationTitleHeight
    } action: {
      isNavigationTitleVisible = $1
    }
    .listStyle(.plain)
    .sheet(isPresented: $model.isNewReminderSheetPresented) {
      if let remindersList = model.detailType.remindersList {
        NavigationStack {
          ReminderFormView(
            reminder: Reminder.Draft(remindersListID: remindersList.id),
            remindersList: remindersList
          )
          .navigationTitle("New Reminder")
        }
      }
    }
    .sheet(item: $model.sharedRecord) { sharedRecord in
      CloudSharingView(sharedRecord: sharedRecord)
    }
    .toolbar {
      ToolbarItem(placement: .principal) {
        Text(model.detailType.navigationTitle)
          .font(.headline)
          .opacity(isNavigationTitleVisible ? 1 : 0)
          .animation(.default.speed(2), value: isNavigationTitleVisible)
      }
      if model.detailType.is(\.remindersList) {
        ToolbarItem(placement: .bottomBar) {
          HStack {
            Button {
              model.isNewReminderSheetPresented = true
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
          .tint(model.detailType.color)
        }
      }
      ToolbarItem(placement: .primaryAction) {
        HStack(alignment: .firstTextBaseline) {
          if model.detailType.is(\.remindersList) {
            Button {
              Task { await model.shareButtonTapped() }
            } label: {
              Image(systemName: "square.and.arrow.up")
            }
          }
          Menu {
            Group {
              Menu {
                ForEach(RemindersDetailModel.Ordering.allCases, id: \.self) { ordering in
                  Button {
                    Task { await model.orderingButtonTapped(ordering) }
                  } label: {
                    Text(ordering.rawValue)
                    ordering.icon
                  }
                }
              } label: {
                Text("Sort By")
                Text(model.ordering.rawValue)
                Image(systemName: "arrow.up.arrow.down")
              }
              Button {
                Task { await model.showCompletedButtonTapped() }
              } label: {
                Text(model.showCompleted ? "Hide Completed" : "Show Completed")
                Image(systemName: model.showCompleted ? "eye.slash.fill" : "eye")
              }
            }
            .tint(model.detailType.color)
          } label: {
            Image(systemName: "ellipsis.circle")
          }
        }
      }
    }
    .toolbarTitleDisplayMode(.inline)
  }

  @ViewBuilder
  var header: some View {
    if let coverImageData = model.coverImageData, let image = UIImage(data: coverImageData) {
      ZStack {
        Image(uiImage: image)
          .resizable()
          .scaledToFill()
          .frame(maxHeight: 200)
          .clipped()

        GeometryReader { proxy in
          Text(model.detailType.navigationTitle)
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(model.detailType.color)
            .padding()
            .background(Color.black.opacity(0.6))
            .cornerRadius(10)
            .padding()
            .onAppear { navigationTitleHeight = proxy.size.height }
        }
      }
      .listRowInsets(EdgeInsets())
    } else {
      VStack(alignment: .leading) {
        GeometryReader { proxy in
          Text(model.detailType.navigationTitle)
            .font(.system(.largeTitle, design: .rounded, weight: .bold))
            .foregroundStyle(model.detailType.color)
            .onAppear { navigationTitleHeight = proxy.size.height }
        }
      }
      .listRowSeparator(.hidden)
    }
  }
}

extension RemindersDetailModel.DetailType {
  fileprivate var id: String {
    switch self {
    case .all: "all"
    case .completed: "completed"
    case .flagged: "flagged"
    case .remindersList(let list): "list_\(list.id)"
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
    case .remindersList(let list): list.title
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
    case .remindersList(let list): list.color
    case .scheduled: .red
    case .tags: .blue
    case .today: .blue
    }
  }
}

struct RemindersDetailPreview: PreviewProvider {
  static var previews: some View {
    let (remindersList, tag) = try! prepareDependencies {
      $0.defaultDatabase = try Reminders.appDatabase()
      return try $0.defaultDatabase.read { db in
        (
          try RemindersList.fetchOne(db)!,
          try Tag.fetchOne(db)!
        )
      }
    }
    let detailTypes: [RemindersDetailModel.DetailType] = [
      .all,
      .remindersList(remindersList),
      .tags([tag]),
    ]
    ForEach(detailTypes, id: \.self) { detailType in
      NavigationStack {
        RemindersDetailView(model: RemindersDetailModel(detailType: detailType))
      }
      .previewDisplayName(detailType.navigationTitle)
    }
  }
}
