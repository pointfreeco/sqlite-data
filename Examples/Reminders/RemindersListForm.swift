import IssueReporting
import SharingGRDB
import SwiftUI

struct RemindersListForm: View {
  @Dependency(\.defaultDatabase) private var database

  @State var remindersList: RemindersList.Draft
  @Environment(\.dismiss) var dismiss

  init(existingList: RemindersList.Draft? = nil) {
    remindersList = existingList ?? RemindersList.Draft(id: UUID())
  }

  var body: some View {
    Form {
      Section {
        VStack {
          TextField("List Name", text: $remindersList.title)
            .font(.system(.title2, design: .rounded, weight: .bold))
            .foregroundStyle(remindersList.color)
            .multilineTextAlignment(.center)
            .padding()
            .textFieldStyle(.plain)
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(.buttonBorder)
      }
      ColorPicker("Color", selection: $remindersList.color)
    }
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem {
        Button("Save") {
          withErrorReporting {
            try database.write { db in
              let query = RemindersList.upsert(remindersList)
              print(query.queryFragment.debugDescription)
              try query
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
      .navigationTitle("New List")
  }
}
