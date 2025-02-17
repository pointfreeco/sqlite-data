import Dependencies
import GRDB
import IssueReporting
import Sharing
import SharingGRDB
import SwiftUI

struct ReminderFormConfig {
  var reminder = Reminder(listID: 0)
  var remindersList = RemindersList() {
    didSet{
      reminder.listID = remindersList.id!
    }
  }
  var selectedTags: [Tag] = []
  
  var isEditing = false
  
  mutating func present(remindersList: RemindersList, reminder: Reminder = Reminder(listID: 0), selectedTags: [Tag] = []) {
    isEditing = true
    self.reminder = reminder
    self.remindersList = remindersList
    self.selectedTags = selectedTags
  }
  
  mutating func save(database: DatabaseWriter) {
    withErrorReporting {
      try database.write { db in
        try reminder.save(db)
        try ReminderTag.filter(Column("reminderID") == reminder.id!).deleteAll(db)
        for tag in selectedTags {
          _ = try ReminderTag(reminderID: reminder.id!, tagID: tag.id!).saved(db)
        }
        isEditing = false
      }
    }
  }
  
  mutating func cancel() {
    isEditing = false
  }
}

struct ReminderFormView: View {
  @SharedReader(.fetchAll(sql: #"SELECT * FROM "remindersLists" ORDER BY "name" ASC"#))
  var remindersLists: [RemindersList]

  @State var isPresentingTagsPopover = false

  @Binding var config: ReminderFormConfig
  
  @Dependency(\.defaultDatabase) private var database

  var body: some View {
    Form {
      TextField("Title", text: $config.reminder.title)
      TextEditor(text: $config.reminder.notes)
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
          TagsPopover(selectedTags: $config.selectedTags)
        }
      }

      Section {
        Toggle(isOn: $config.reminder.isDateSet.animation()) {
          HStack {
            Image(systemName: "calendar.circle.fill")
              .font(.title)
              .foregroundStyle(.red)
            Text("Date")
          }
        }
        if let date = config.reminder.date {
          DatePicker(
            "",
            selection: $config.reminder.date[coalesce: date],
            displayedComponents: [.date, .hourAndMinute]
          )
          .padding([.top, .bottom], 2)
        }
      }

      Section {
        Toggle(isOn: $config.reminder.isFlagged) {
          HStack {
            Image(systemName: "flag.circle.fill")
              .font(.title)
              .foregroundStyle(.red)
            Text("Flag")
          }
        }
        Picker(selection: $config.reminder.priority) {
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

        Picker(selection: $config.remindersList) {
          ForEach(remindersLists) { remindersList in
            Text(remindersList.name)
              .tag(remindersList)
              .buttonStyle(.plain)
          }
        } label: {
          HStack {
            Image(systemName: "list.bullet.circle.fill")
              .font(.title)
              .foregroundStyle(Color.hex(config.remindersList.color))
            Text("List")
          }
        }
      }
    }
    .navigationTitle(config.remindersList.name)
    .toolbar {
      ToolbarItem {
        Button("Save") { config.save(database: database) }
      }
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          config.cancel()
        }
      }
    }
  }

  private var tagsDetail: Text {
    config.selectedTags.reduce(Text("")) { result, tag in
      result + Text("#\(tag.name) ")
    }
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
  @Previewable @State var config = {
    let (remindersList, reminder) = try! prepareDependencies {
      $0.defaultDatabase = try Reminders.appDatabase(inMemory: true)
      return try $0.defaultDatabase.write { db in
        let remindersList = try RemindersList.fetchOne(db)!
        return (
          remindersList,
          try Reminder.filter(Column("listID") == remindersList.id).fetchOne(db)!
        )
      }
    }
    return ReminderFormConfig(reminder: reminder, remindersList: remindersList)
  }()
  
  NavigationStack {
    ReminderFormView(config: $config)
  }
}
