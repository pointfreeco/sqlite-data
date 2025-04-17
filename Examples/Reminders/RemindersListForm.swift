import Dependencies
import GRDB
import IssueReporting
import SwiftUI

struct RemindersListForm: View {
  @Dependency(\.defaultDatabase) private var database

  @State var remindersList: RemindersList.Draft
  @Environment(\.dismiss) var dismiss

  init(existingList: RemindersList.Draft? = nil) {
    remindersList = existingList ?? RemindersList.Draft()
  }

  var body: some View {
    Form {
      TextField("Name", text: $remindersList.name)
      ColorPicker("Color", selection: $remindersList.color)
    }
    .toolbar {
      ToolbarItem {
        Button("Save") {
          withErrorReporting {
            try database.write { db in
              try RemindersList.upsert(remindersList)
                .execute(db)
            }
          }
          dismiss()
        }
      }
      ToolbarItem(placement: .cancellationAction) {
        Button("Cancel") {
          dismiss()
        }
      }
    }
  }
}

#Preview {
  let _ = try! prepareDependencies {
    $0.defaultDatabase = try Reminders.appDatabase()
  }
  NavigationStack {
    RemindersListForm()
  }
}
