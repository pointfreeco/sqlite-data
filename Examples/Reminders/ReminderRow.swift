import SQLiteData
import SwiftUI

struct ReminderRow: View {
  let color: Color
  let isPastDue: Bool
  let notes: String
  let reminder: Reminder
  let remindersList: RemindersList
  let showCompleted: Bool
  let tags: String
  let title: String?

  @State var editReminder: Reminder.Draft?

  @Dependency(\.defaultDatabase) private var database

  init(
    color: Color,
    isPastDue: Bool,
    notes: String,
    reminder: Reminder,
    remindersList: RemindersList,
    showCompleted: Bool,
    tags: String,
    title: String? = nil
  ) {
    self.color = color
    self.isPastDue = isPastDue
    self.notes = notes
    self.reminder = reminder
    self.remindersList = remindersList
    self.showCompleted = showCompleted
    self.tags = tags
    self.title = title
  }

  var body: some View {
    HStack {
      HStack(alignment: .firstTextBaseline) {
        Button(action: completeButtonTapped) {
          Image(systemName: reminder.isCompleted ? "circle.inset.filled" : "circle")
            .foregroundStyle(.gray)
            .font(.title2)
            .padding([.trailing], 5)
        }
        VStack(alignment: .leading) {
          title(for: reminder, title: title)

          if !notes.isEmpty {
            highlight(notes)
              .font(.subheadline)
              .foregroundStyle(.gray)
              .lineLimit(2)
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
            editReminder = Reminder.Draft(reminder)
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
        editReminder = Reminder.Draft(reminder)
      }
    }
    .sheet(item: $editReminder) { reminder in
      NavigationStack {
        ReminderFormView(reminder: reminder, remindersList: remindersList)
          .navigationTitle("Details")
      }
    }
  }

  private func completeButtonTapped() {
    withErrorReporting {
      try database.write { db in
        try Reminder
          .find(reminder.id)
          .update { $0.toggleStatus() }
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
    Text(
      """
      \(dueText)\(reminder.dueDate == nil ? "" : " ")\(highlight(tags).foregroundStyle(.gray))
      """
    )
    .font(.callout)
  }

  @ViewBuilder
  private func title(for reminder: Reminder, title: String?) -> some View {
    HStack(alignment: .firstTextBaseline) {
      if let priority = reminder.priority {
        Text(String(repeating: "!", count: priority.rawValue))
          .foregroundStyle(reminder.isCompleted ? .gray : remindersList.color)
      }
      highlight(title ?? reminder.title)
        .foregroundStyle(reminder.isCompleted ? .gray : .primary)
    }
    .font(.title3)
  }

  func highlight(_ text: String) -> Text {
    if let attributedText = try? AttributedString(markdown: text) {
      Text(attributedText)
    } else {
      Text(text)
    }
  }
}

struct ReminderRowPreview: PreviewProvider {
  static var previews: some View {
    var reminder: Reminder!
    var remindersList: RemindersList!
    let _ = try! prepareDependencies {
      $0.defaultDatabase = try Reminders.appDatabase()
      try $0.defaultDatabase.read { db in
        reminder = try Reminder.fetchOne(db)
        remindersList = try RemindersList.fetchOne(db)!
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
          showCompleted: true,
          tags: "#point-free #adulting"
        )
      }
    }
  }
}
