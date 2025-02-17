import Dependencies
import SwiftUI

struct ReminderRow: View {
  let isPastDue: Bool
  let reminder: Reminder
  let remindersList: RemindersList
  let tags: [String]

  @State var editReminder: Reminder?

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
            editReminder = reminder
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
        editReminder = reminder
      }
    }
    .sheet(item: $editReminder) { reminder in
      NavigationStack {
        ReminderFormView(existingReminder: reminder, remindersList: remindersList)
      }
    }
  }

  private func completeButtonTapped() {
    withErrorReporting {
      try database.write { db in
        var reminder = reminder
        reminder.isCompleted.toggle()
        _ = try reminder.saved(db)
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
        .foregroundStyle(reminder.isCompleted ? .gray : Color.hex(remindersList.color))
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
        remindersList: reminderList,
        tags: ["point-free", "adulting"]
      )
    }
  }
}
