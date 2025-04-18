import Dependencies
import SharingGRDB
import SwiftUI

struct ReminderRow: View {
  let color: Color
  let isPastDue: Bool
  let notes: String
  let reminder: Reminder
  let remindersList: RemindersList
  let tags: [String]

  @State var editReminder: Reminder?
  @State var isCompleted: Bool

  @Dependency(\.defaultDatabase) private var database

  init(
    color: Color,
    isPastDue: Bool,
    notes: String,
    reminder: Reminder,
    remindersList: RemindersList,
    tags: [String],
    editReminder: Reminder? = nil
  ) {
    self.color = color
    self.isPastDue = isPastDue
    self.notes = notes
    self.reminder = reminder
    self.remindersList = remindersList
    self.tags = tags
    self.editReminder = editReminder
    self.isCompleted = reminder.isCompleted
  }

  var body: some View {
    HStack {
      HStack(alignment: .top) {
        Button(action: completeButtonTapped) {
          Image(systemName: isCompleted ? "circle.inset.filled" : "circle")
            .foregroundStyle(.gray)
            .font(.title2)
            .padding([.trailing], 5)
        }
        VStack(alignment: .leading) {
          title(for: reminder)

          if !notes.isEmpty {
            Text(notes)
              .lineLimit(2)
              .foregroundStyle(.gray)
          }
          subtitleText
        }
      }
      Spacer()
      if !isCompleted {
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
          .tint(color)
        }
      }
    }
    .buttonStyle(.borderless)
    .swipeActions {
      Button("Delete", role: .destructive) {
        withErrorReporting {
          try database.write { db in
            try Reminder.delete(reminder).execute(db)
          }
        }
      }
      Button(reminder.isFlagged ? "Unflag" : "Flag") {
        withErrorReporting {
          try database.write { db in
            try Reminder
              .find(reminder.id)
              .update { $0.isFlagged.toggle() }
              .execute(db)
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
    .task(id: isCompleted) {
      guard
        isCompleted,
        isCompleted != reminder.isCompleted
      else { return }
      do {
        try await Task.sleep(for: .seconds(2))
        toggleCompletion()
      } catch {}
    }
  }

  private func completeButtonTapped() {
    self.isCompleted.toggle()
    if !self.isCompleted {
      toggleCompletion()
    }
  }

  private func toggleCompletion() {
    withErrorReporting {
      try database.write { db in
        try Reminder
          .find(reminder.id)
          .update { $0.isCompleted.toggle() }
          .execute(db)
      }
    }
  }

  private var dueText: Text {
    if let date = reminder.dueDate {
      Text(date.formatted(date: .numeric, time: .shortened))
        .foregroundStyle(isPastDue ? .red : .gray)
    } else {
      Text("")
    }
  }

  private var subtitleText: Text {
    let tagsText = tags.reduce(Text(reminder.dueDate == nil ? "" : "  ")) { result, tag in
      result + Text("#\(tag) ")
    }
    return
      (dueText
      + tagsText
      .foregroundStyle(.gray)
      .bold())
      .font(.callout)
  }

  private func title(for reminder: Reminder) -> some View {
    let exclamations =
      String(repeating: "!", count: reminder.priority?.rawValue ?? 0)
      + (reminder.priority == nil ? "" : " ")
    return
      (Text(exclamations)
      .foregroundStyle(isCompleted ? .gray : remindersList.color)
      + Text(reminder.title)
      .foregroundStyle(isCompleted ? .gray : .primary))
      .font(.title3)
  }
}

struct ReminderRowPreview: PreviewProvider {
  static var previews: some View {
    var reminder: Reminder!
    var remindersList: RemindersList!
    let _ = try! prepareDependencies {
      $0.defaultDatabase = try Reminders.appDatabase()
      try $0.defaultDatabase.read { db in
        reminder = try Reminder.all.fetchOne(db)
        remindersList = try RemindersList.all.fetchOne(db)!
      }
    }

    NavigationStack {
      List {
        ReminderRow(
          color: remindersList.color,
          isPastDue: false,
          notes: reminder.notes.replacingOccurrences(of: "\n", with: " "),
          reminder: reminder,
          remindersList: remindersList,
          tags: ["point-free", "adulting"]
        )
      }
    }
  }
}
