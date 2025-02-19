import Dependencies
// TODO: Comment this out and the error messages are bad
import StructuredQueriesGRDB
import SwiftUI
import SwiftUINavigation

struct ReminderRow: View {
  let isPastDue: Bool
  let reminder: Reminder
  let remindersListColor: Int
  let tags: [String]

  @State var editReminder: (Reminder, RemindersList)?

  @Dependency(\.defaultDatabase) private var database
  
  var body: some View {
    HStack {
      HStack(alignment: .top) {
        Button(action: completeButtonTapped) {
          Image(systemName: reminder.isCompleted ? "circle.inset.filled": "circle")
            .foregroundStyle(.gray)
            .font(.title2)
            .padding([.trailing], 5)
        }
        VStack(alignment: .leading) {
          title(for: reminder)

          let notes = reminder.notes
            .split(separator: "\n", omittingEmptySubsequences: true)
            .prefix(3)
            .joined(separator: " ")
          if !notes.isEmpty {
            Text(notes)
              .lineLimit(2)
              .foregroundStyle(.gray)
          }
          subtitleText
        }
      }
      Spacer()
      if !reminder.isCompleted {
        HStack {
          if reminder.isFlagged {
            Image(systemName: "flag.fill")
              .foregroundStyle(.orange)
          }
          Button {
            presentEditReminder()
          } label: {
            Image(systemName: "info.circle")
          }
        }
      }
    }
    .buttonStyle(.borderless)
    .swipeActions {
      Button("Delete") {
        withErrorReporting {
          do {
            _ = try database.write { db in
              try reminder.delete(db)
            }
          }
        }
      }
      .tint(.red)
      Button(reminder.isFlagged ? "Unflag" : "Flag") {
        withErrorReporting {
          try database.write { db in
            var reminder = reminder
            reminder.isFlagged.toggle()
            _ = try reminder.saved(db)
          }
        }
      }
      .tint(.orange)
      Button("Details") {
        presentEditReminder()
      }
    }
    .sheet(item: $editReminder, id: \.0.id) { reminder, remindersList in
      NavigationStack {
        ReminderFormView(existingReminder: reminder, remindersList: remindersList)
      }
    }
  }

  private func presentEditReminder() {
    withErrorReporting {
      try database.read { db in
        // TODO: try RemindersList.find(reminder.listID)?
        let remindersList = try RemindersList.where { $0.id == reminder.listID }.fetchOne(db)
        editReminder = (reminder, remindersList!)
      }
    }
  }

  private func completeButtonTapped() {
    withErrorReporting {
      try database.write { db in
        try Reminder
          .where { $0.id == reminder.id }
          .update { $0.isCompleted.toggle() }
          .execute(db)
      }
    }
  }

  private var dueText: Text {
    if let date = reminder.date {
      Text(date.formatted(date: .numeric, time: .shortened))
        .foregroundStyle(isPastDue ? .red : .gray)
    } else {
      Text("")
    }
  }

  private var subtitleText: Text {
    let tagsText = tags.reduce(Text(reminder.date == nil ? "" : "  ")) { result, tag in
      result + Text("#\(tag) ")
        .foregroundStyle(.gray)
        .bold()
    }
    return (dueText + tagsText).font(.callout)
  }
  
  private func title(for reminder: Reminder) -> some View {
    let exclamations = String(repeating: "!", count: reminder.priority ?? 0)
    + (reminder.priority == nil ? "" : " ")
    return (
      Text(exclamations)
        .foregroundStyle(reminder.isCompleted ? .gray : Color.hex(remindersListColor))
      + Text(reminder.title)
        .foregroundStyle(reminder.isCompleted ? .gray : .primary)
    )
    .font(.title3)
  }
}

#Preview {
  var reminder: Reminder!
  var reminderList: RemindersList!
  let _ = try! prepareDependencies {
    $0.defaultDatabase = try Reminders.appDatabase(inMemory: true)
    try $0.defaultDatabase.read { db in
      reminder = try Reminder.fetchOne(db)
      reminderList = try RemindersList.fetchOne(db)!
    }
  }
  
  NavigationStack {
    List {
      ReminderRow(
        isPastDue: false,
        reminder: reminder,
        remindersListColor: 0xff0000,
        tags: ["point-free", "adulting"]
      )
    }
  }
}
