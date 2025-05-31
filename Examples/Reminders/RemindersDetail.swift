import CasePaths
import SharingGRDB
import SwiftUI

struct RemindersDetailView: View {
  @FetchAll private var sectionRows: [SectionState]
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
    _sectionRows = FetchAll(sectionsQuery, animation: .default)
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
      ForEach(sectionRows) { sectionRow in
        Section {
          ForEach(sectionRow.reminders) { reminder in
            ReminderRow(
              color: detailType.color,
              isPastDue: false,
              //reminderState.isPastDue,
              notes: "",
              //reminderState.notes,
              reminder: reminder,
              //reminderState.reminder,
              remindersList: sectionRow.remindersList ?? RemindersList(id: UUID()),// reminderState.remindersList,
              showCompleted: showCompleted,
              tags: [] //reminderState.tags
            )
          }
        } header: {
          Text(sectionRow.remindersSection?.title ?? "Others")
            .font(.system(.title, design: .rounded, weight: .bold))
            .foregroundStyle(sectionRow.remindersSection == nil ? Color.secondary : Color.primary)
            .padding([.top, .bottom], 6)
        }
      }
      .onMove { indexSet, index in
        move(from: indexSet, to: index)
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

  func move(from source: IndexSet, to destination: Int) {
//    withErrorReporting {
//      try database.write { db in
//        var ids = reminderStates.map(\.reminder.id)
//        ids.move(fromOffsets: source, toOffset: destination)
//        try Reminder
//          .where { $0.id.in(ids) }
//          .update {
//            let ids = Array(ids.enumerated())
//            let (first, rest) = (ids.first!, ids.dropFirst())
//            $0.position =
//            rest
//              .reduce(Case($0.id).when(first.element, then: first.offset)) { cases, id in
//                cases.when(id.element, then: id.offset)
//              }
//              .else($0.position)
//          }
//          .execute(db)
//      }
//    }
    ordering = .manual
  }

  private enum Ordering: String, CaseIterable {
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
    case list(RemindersList)
    case scheduled
    case tags([Tag])
    case today
  }

  private func updateQuery() async throws {
    try await $sectionRows.load(sectionsQuery)
  }

  fileprivate var sectionsQuery: some StructuredQueries.Statement<SectionState> {
    let query = RemindersSection
    // TODO: eq is not defined on (_, ?) ?
      .fullJoin(remindersQuery) {
//        (showCompleted || !$1.isCompleted)
//        &&
        $1.remindersSectionID.eq($0.id)
      }
      .leftJoin(ReminderTag.all) { $1.id.eq($2.reminderID) }
      .leftJoin(Tag.all) { $2.tagID.eq($3.id) }
      .where { _, reminder, _, tag in
        switch detailType {
        case .all: #sql("NOT \(reminder.isCompleted)")
        case .completed: #sql("\(reminder.isCompleted)")
        case .flagged: #sql("\(reminder.isFlagged)")
        case .list(let list):
          #sql("\(reminder.remindersListID.eq(list.id)) OR \(reminder.remindersListID) IS NULL")
        case .scheduled: #sql("\(reminder.isScheduled)")
        case .tags(let tags): tag.id.ifnull(UUID(0)).in(tags.map(\.id))
        case .today: #sql("\(reminder.isToday)")
        }
      }
      .leftJoin(RemindersList.all) { $1.remindersListID.eq($4.id) }
      .select { remindersSection, reminder, _, tag, remindersList in
        SectionState.Columns(
          remindersList: remindersList,
          remindersSection: remindersSection,
          reminders: #sql("\(reminder.jsonGroupArray(filter: reminder.id.isNot(nil)))")
        )
      }
      .group { _, reminder, _, _, _ in reminder.remindersSectionID }
    return query
  }

  fileprivate var remindersQuery: some StructuredQueries.SelectStatementOf<Reminder> {
    Reminder
      .where {
        if !showCompleted {
          !$0.isCompleted
        }
      }
      .order { $0.isCompleted }
      .order {
        switch ordering {
        case .dueDate: $0.dueDate.asc(nulls: .last)
        case .manual: $0.position
        case .priority: ($0.priority.desc(), $0.isFlagged.desc())
        case .title: $0.title
        }
      }
  }

  @Selection
  fileprivate struct SectionState: Identifiable {
    var id: RemindersSection.ID? { remindersSection?.id }
    let remindersList: RemindersList?
    let remindersSection: RemindersSection?
    @Column(as: [Reminder].JSONRepresentation.self)
    let reminders: [Reminder]
  }

  @Selection
  fileprivate struct ReminderState: Identifiable {
    var id: Reminder.ID { reminder.id }
    let reminder: Reminder
    let remindersList: RemindersList
    let isPastDue: Bool
    let notes: String
    @Column(as: [String].JSONRepresentation.self)
    let tags: [String]
  }
}

extension RemindersDetailView.DetailType {
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

struct RemindersDetailPreview: PreviewProvider {
  static var previews: some View {
    let (remindersList, tag) = try! prepareDependencies {
      $0.defaultDatabase = try Reminders.appDatabase(seed: true)
      return try $0.defaultDatabase.read { db in
        (
          try RemindersList.limit(1, offset: 2).fetchOne(db)!,
          try Tag.all.fetchOne(db)!
        )
      }
    }
    let detailTypes: [RemindersDetailView.DetailType] = [
//      .all,
      .list(remindersList),
//      .tags([tag]),
    ]
    ForEach(detailTypes, id: \.self) { detailType in
      NavigationStack {
        RemindersDetailView(detailType: detailType)
      }
      .previewDisplayName(detailType.navigationTitle)
    }
  }
}
