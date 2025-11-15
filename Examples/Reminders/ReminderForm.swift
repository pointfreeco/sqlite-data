import IssueReporting
import SQLiteData
import SwiftUI

struct ReminderFormView: View {
  @FetchAll(RemindersList.order(by: \.title)) var remindersLists
  @FetchOne var remindersList: RemindersList

  @State var isPresentingTagsPopover = false
  @State var reminder: Reminder.Draft
  @State var selectedTags: [Tag] = []

  @Dependency(\.defaultDatabase) private var database
  @Environment(\.dismiss) var dismiss

  init(reminder: Reminder.Draft, remindersList: RemindersList) {
    _remindersList = FetchOne(wrappedValue: remindersList, RemindersList.find(remindersList.id))
    self.reminder = reminder
  }

  var body: some View {
    Form {
      TextField("Title", text: $reminder.title)

      ZStack {
        if reminder.notes.isEmpty {
          TextEditor(text: .constant("Notes"))
            .foregroundStyle(.placeholder)
            .accessibilityHidden(true, isEnabled: false)
        }

        TextEditor(text: $reminder.notes)
      }
      .lineLimit(4)
      .padding([.leading, .trailing], -5)

      Section {
        Button {
          isPresentingTagsPopover = true
        } label: {
          HStack {
            Image(systemName: "number.square.fill")
              .font(.title)
              .foregroundStyle(.gray)
            Text("Tags")
              .foregroundStyle(Color(.label))
            Spacer()
            if let tagsDetail {
              tagsDetail
                .lineLimit(1)
                .truncationMode(.tail)
                .font(.callout)
                .foregroundStyle(.gray)
            }
            Image(systemName: "chevron.right")
          }
        }
      }
      .popover(isPresented: $isPresentingTagsPopover) {
        NavigationStack {
          TagsView(selectedTags: $selectedTags)
        }
      }

      Section {
        Toggle(isOn: $reminder.isDateSet.animation()) {
          HStack {
            Image(systemName: "calendar.circle.fill")
              .font(.title)
              .foregroundStyle(.red)
            Text("Date")
          }
        }
        if let dueDate = reminder.dueDate {
          DatePicker(
            "",
            selection: $reminder.dueDate[coalesce: dueDate],
            displayedComponents: [.date, .hourAndMinute]
          )
          .padding([.top, .bottom], 2)
        }
      }

      Section {
        Toggle(isOn: $reminder.isFlagged) {
          HStack {
            Image(systemName: "flag.circle.fill")
              .font(.title)
              .foregroundStyle(.red)
            Text("Flag")
          }
        }
        Picker(selection: $reminder.priority) {
          Text("None").tag(Reminder.Priority?.none)
          Divider()
          Text("High").tag(Reminder.Priority.high)
          Text("Medium").tag(Reminder.Priority.medium)
          Text("Low").tag(Reminder.Priority.low)
        } label: {
          HStack {
            Image(systemName: "exclamationmark.circle.fill")
              .font(.title)
              .foregroundStyle(.red)
            Text("Priority")
          }
        }

        Picker(selection: $reminder.remindersListID) {
          ForEach(remindersLists) { remindersList in
            Text(remindersList.title)
              .tag(remindersList)
              .buttonStyle(.plain)
              .tag(remindersList.id)
          }
        } label: {
          HStack {
            Image(systemName: "list.bullet.circle.fill")
              .font(.title)
              .foregroundStyle(remindersList.color)
            Text("List")
          }
        }
        .task(id: reminder.remindersListID) {
          await withErrorReporting {
            try await $remindersList.load(RemindersList.find(reminder.remindersListID))
          }
        }
      }
    }
    .padding(.top, -28)
    .task {
      guard let reminderID = reminder.id
      else { return }
      do {
        selectedTags = try await database.read { db in
          try Tag
            .order(by: \.title)
            .join(ReminderTag.all) { $0.primaryKey.eq($1.tagID) }
            .where { $1.reminderID.eq(reminderID) }
            .select { tag, _ in tag }
            .fetchAll(db)
        }
      } catch {
        selectedTags = []
        reportIssue(error)
      }
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem {
        Button(action: saveButtonTapped) {
          Text("Save")
        }
      }
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
    }
  }

  private var tagsDetail: Text? {
    guard let tag = selectedTags.first else { return nil }
    return selectedTags.dropFirst().reduce(Text("#\(tag.title)")) { result, tag in
      result + Text(" #\(tag.title) ")
    }
  }

  private func saveButtonTapped() {
    withErrorReporting {
      try database.write { db in
        let reminderID = try Reminder.upsert { reminder }
          .returning(\.id)
          .fetchOne(db)!
        try ReminderTag
          .where { $0.reminderID.eq(reminderID) }
          .delete()
          .execute(db)
        try ReminderTag.insert {
          selectedTags.map { tag in
            ReminderTag.Draft(reminderID: reminderID, tagID: tag.id)
          }
        }
        .execute(db)
      }
    }
    dismiss()
  }
}

extension Reminder.Draft {
  fileprivate var isDateSet: Bool {
    get { dueDate != nil }
    set { dueDate = newValue ? Date() : nil }
  }
}

extension Optional {
  fileprivate subscript(coalesce coalesce: Wrapped) -> Wrapped {
    get { self ?? coalesce }
    set { self = newValue }
  }
}

struct ReminderFormPreview: PreviewProvider {
  static var previews: some View {
    let (remindersList, reminder) = try! prepareDependencies {
      $0.defaultDatabase = try Reminders.appDatabase()
      return try $0.defaultDatabase.write { db in
        let remindersList = try RemindersList.fetchOne(db)!
        return (
          remindersList,
          try Reminder.where { $0.remindersListID.eq(remindersList.id) }.fetchOne(db)!
        )
      }
    }
    NavigationStack {
      ReminderFormView(reminder: Reminder.Draft(reminder), remindersList: remindersList)
        .navigationTitle("Detail")
    }
  }
}
