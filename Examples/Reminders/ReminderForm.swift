import Dependencies
import GRDB
import IssueReporting
import SharingGRDB
import StructuredQueriesGRDB
import SwiftUI

struct ReminderFormView: View {
  @SharedReader(.fetchAll(RemindersList.order(by: \.name))) var remindersLists

  @State var isPresentingTagsPopover = false
  @State var remindersList: RemindersList
  @State var reminder: Reminder.Draft
  @State var selectedTags: [Tag] = []

  @Dependency(\.defaultDatabase) private var database
  @Environment(\.dismiss) var dismiss

  init(existingReminder: Reminder? = nil, remindersList: RemindersList) {
    self.remindersList = remindersList
    if let existingReminder {
      reminder = Reminder.Draft(existingReminder)
    } else {
      reminder = Reminder.Draft(remindersListID: remindersList.id)
    }
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
              .foregroundStyle(.black)
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
          Text("None").tag(Priority?.none)
          Divider()
          Text("High").tag(Priority.high)
          Text("Medium").tag(Priority.medium)
          Text("Low").tag(Priority.low)
        } label: {
          HStack {
            Image(systemName: "exclamationmark.circle.fill")
              .font(.title)
              .foregroundStyle(.red)
            Text("Priority")
          }
        }

        Picker(selection: $remindersList) {
          ForEach(remindersLists) { remindersList in
            Text(remindersList.name)
              .tag(remindersList)
              .buttonStyle(.plain)
          }
        } label: {
          HStack {
            Image(systemName: "list.bullet.circle.fill")
              .font(.title)
              .foregroundStyle(remindersList.color)
            Text("List")
          }
        }
        .onChange(of: remindersList) {
          reminder.remindersListID = remindersList.id
        }
      }
    }
    .task {
      guard let reminderID = reminder.id
      else { return }
      do {
        selectedTags = try await database.read { db in
          try Tag.select(\.self)
            .order(by: \.name)
            .join(ReminderTag.all) { $0.id.eq($1.tagID) }
            .where { $1.reminderID.eq(reminderID) }
            .fetchAll(db)
        }
      } catch {
        selectedTags = []
        reportIssue(error)
      }
    }
    .navigationTitle(remindersList.name)
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
    return selectedTags.dropFirst().reduce(Text("#\(tag.name)")) { result, tag in
      result + Text(" #\(tag.name) ")
    }
  }

  private func saveButtonTapped() {
    withErrorReporting {
      try database.write { db in
        let reminderID = try Reminder.upsert(reminder).returning(\.id).fetchOne(db)!
        try ReminderTag.where { $0.reminderID.eq(reminderID) }
          .delete()
          .execute(db)
        try ReminderTag.insert(
          selectedTags.map { tag in
            ReminderTag(reminderID: reminderID, tagID: tag.id)
          }
        )
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
        let remindersList = try RemindersList.all.fetchOne(db)!
        return (
          remindersList,
          try Reminder.where { $0.remindersListID == remindersList.id }.fetchOne(db)!
        )
      }
    }
    NavigationStack {
      ReminderFormView(existingReminder: reminder, remindersList: remindersList)
    }
  }
}
