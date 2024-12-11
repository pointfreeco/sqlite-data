import Dependencies
import GRDB
import IssueReporting
import Sharing
import SharingGRDB
import SwiftUI

struct ReminderFormView: View {
  @SharedReader(.fetchAll(sql: #"SELECT * FROM "remindersLists" ORDER BY "name" ASC"#))
  var remindersLists: [RemindersList]

  @State var isPresentingTagsPopover = false
  @State var remindersList: RemindersList
  @State var reminder: Reminder
  @State var selectedTags: [Tag]

  @Dependency(\.defaultDatabase) private var database
  @Environment(\.dismiss) var dismiss

  init?(existingReminder: Reminder? = nil, remindersList: RemindersList) {
    _remindersList = State(wrappedValue: remindersList)
    if let existingReminder, let reminderID = existingReminder.id {
      _reminder = State(wrappedValue: existingReminder)
      do {
        let tags = try _database.wrappedValue.read { db in
          try Tag.all()
            .joining(optional: Tag.hasMany(ReminderTag.self))
            .filter(Column("reminderID").detached == reminderID)
            .order(Column("name"))
            .fetchAll(db)
        }
        _selectedTags = State(wrappedValue: tags)
      } catch {
        _selectedTags = State(wrappedValue: [])
        reportIssue(error)
      }
    } else if let listID = remindersList.id {
      _reminder = State(wrappedValue: Reminder(listID: listID))
      _selectedTags = State(wrappedValue: [])
    } else {
      reportIssue("'list.id' is required to be non-nil.")
      return nil
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
          reminder.listID = remindersList.id!
        }
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
        try reminder.save(db)
        try ReminderTag.filter(Column("reminderID") == reminder.id!).deleteAll(db)
        for tag in selectedTags {
          _ = try ReminderTag(reminderID: reminder.id!, tagID: tag.id!).saved(db)
        }
      }
    }
    dismiss()
  }
}

extension Reminder {
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
  @SharedReader(.fetchAll(sql: #"SELECT * FROM "tags" ORDER BY "name" ASC"#))
  var availableTags: [Tag]

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
  let (remindersList, reminder) = prepareDependencies {
    $0.defaultDatabase = .appDatabase
    return try! $0.defaultDatabase.write { db in
      let remindersList = try RemindersList.fetchOne(db)!
      return (
        remindersList,
        try Reminder.filter(Column("listID") == remindersList.id).fetchOne(db)!
      )
    }
  }
  NavigationStack {
    ReminderFormView(existingReminder: reminder, remindersList: remindersList)
  }
}
