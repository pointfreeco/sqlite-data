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
  let reminderID: Reminder.ID?
  @State var reminder: Reminder.Draft
  @State var selectedTags: [Tag] = []

  @Dependency(\.defaultDatabase) private var database
  @Environment(\.dismiss) var dismiss

  init?(existingReminder: Reminder? = nil, remindersList: RemindersList) {
    self.remindersList = remindersList
    if let existingReminder {
      reminderID = existingReminder.id
      reminder = Reminder.Draft(
        date: existingReminder.date,
        isCompleted: existingReminder.isCompleted,
        isFlagged: existingReminder.isFlagged,
        listID: existingReminder.listID,
        notes: existingReminder.notes,
        priority: existingReminder.priority,
        title: existingReminder.title
      )
    } else {
      reminderID = nil
      reminder = Reminder.Draft(listID: remindersList.id)
    }
  }

  var body: some View {
    Form {
      TextField("Title", text: $reminder.title)
      TextEditor(text: $reminder.notes)
        .lineLimit(4)

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
            tagsDetail
              .lineLimit(1)
              .truncationMode(.tail)
              .font(.callout)
              .foregroundStyle(.gray)
            Image(systemName: "chevron.right")
          }
        }
      }
      .popover(isPresented: $isPresentingTagsPopover) {
        NavigationStack {
          TagsPopover(selectedTags: $selectedTags)
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
        if let date = reminder.date {
          DatePicker(
            "",
            selection: $reminder.date[coalesce: date],
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
          Text("None").tag(Int?.none)
          Divider()
          Text("High").tag(3)
          Text("Medium").tag(2)
          Text("Low").tag(1)
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
              .foregroundStyle(Color.hex(remindersList.color))
            Text("List")
          }
        }
        .onChange(of: remindersList) {
          reminder.listID = remindersList.id
        }
      }
    }
    .task {
      do {
        selectedTags = try await database.read { db in
          try Tag.all()
            .order(by: \.name)
            .leftJoin(ReminderTag.all()) { $0.id == $1.tagID }
            .where { $1.reminderID == reminderID }
            .select { tag, _ in tag }
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

  private var tagsDetail: Text {
    selectedTags.reduce(Text("")) { result, tag in
      result + Text("#\(tag.name) ")
    }
  }

  private func saveButtonTapped() {
    withErrorReporting {
      try database.write { db in
        //        try reminder.save(db)
        let updatedReminderID: Reminder.ID
        /*
         let updatedReminderID = Reminder.upsert(id: reminderID, reminder).returning(\.id)

         // If Draft had `id?`:
         let updatedReminderID = Reminder.upsert(reminder).returning(\.id)
         */
        if let reminderID {
          updatedReminderID = try Reminder
            .where { $0.id == reminderID }
            .update {
              // TODO:
              // $0.date = reminder.date
              $0.isCompleted = reminder.isCompleted
              $0.isFlagged = reminder.isFlagged
              $0.listID = reminder.listID
              $0.notes = reminder.notes
              $0.priority = reminder.priority
              $0.title = reminder.title
            }
            .returning(\.id)
            .fetchOne(db)!
          // TODO: This should be on this branch on 'main'
          try db.execute(ReminderTag.where { $0.reminderID == reminderID }.delete())
        } else {
          updatedReminderID = try Reminder.insert(reminder).returning(\.id).fetchOne(db)!
        }
        try db.execute(
          ReminderTag.insert(
            selectedTags.map { tag in
              ReminderTag(reminderID: updatedReminderID, tagID: tag.id)
            }
          )
        )
      }
    }
    dismiss()
  }
}

extension Reminder.Draft {
  fileprivate var isDateSet: Bool {
    get { date != nil }
    set { date = newValue ? Date() : nil }
  }
}
extension Optional {
  fileprivate subscript(coalesce coalesce: Wrapped) -> Wrapped {
    get { self ?? coalesce }
    set { self = newValue }
  }
}

struct TagsPopover: View {
  @SharedReader(.fetchAll(Tag.order(by: \.name))) var availableTags

  @Binding var selectedTags: [Tag]

  @Environment(\.dismiss) var dismiss

  var body: some View {
    List {
      let selectedTagIDs = Set(selectedTags.map(\.id))
      ForEach(availableTags, id: \.id) { tag in
        let tagIsSelected = selectedTagIDs.contains(tag.id)
        Button {
          if tagIsSelected {
            selectedTags.removeAll(where: { $0.id == tag.id })
          } else {
            selectedTags.append(tag)
          }
        } label: {
          HStack {
            if tagIsSelected {
              Image.init(systemName: "checkmark")
            }
            Text(tag.name)
          }
        }
        .tint(tagIsSelected ? .blue : .black)
      }
    }
    .toolbar {
      ToolbarItem {
        Button("Done") { dismiss() }
      }
    }
    .navigationTitle(Text("Tags"))
  }
}

#Preview {
  let (remindersList, reminder) = try! prepareDependencies {
    $0.defaultDatabase = try Reminders.appDatabase(inMemory: true)
    return try $0.defaultDatabase.write { db in
      let remindersList = try RemindersList.fetchOne(db)!
      return (
        remindersList,
        // TODO: Preview bug, use preview provider
//        try Reminder.where { $0.listID == remindersList.id }.fetchOne(db)!
        try Reminder.filter(Column("listID") == remindersList.id).fetchOne(db)!
      )
    }
  }
  NavigationStack {
    ReminderFormView(existingReminder: reminder, remindersList: remindersList)
  }
}
