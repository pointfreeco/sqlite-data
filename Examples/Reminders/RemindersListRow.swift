import SharingGRDB
import StructuredQueriesGRDB
import SwiftUI

struct RemindersListRow: View {
  let reminderCount: Int
  let remindersList: RemindersList

  @State var editList: RemindersList?

  @Dependency(\.defaultDatabase) private var database

  var body: some View {
    HStack {
      Image(systemName: "list.bullet.circle.fill")
        .font(.title)
        .foregroundStyle(Color.hex(remindersList.color))
      Text(remindersList.name)
      Spacer()
      Text("\(reminderCount)")
    }
    .swipeActions {
      Button {
        withErrorReporting {
          _ = try database.write { db in
            try RemindersList
              .where { $0.id == remindersList.id }
              .delete()
              .execute(db)
          }
        }
      } label: {
        Image(systemName: "trash")
      }
      .tint(.red)
      Button {
        editList = remindersList
      } label: {
        Image(systemName: "info.circle")
      }
    }
    .sheet(item: $editList) { list in
      NavigationStack {
        RemindersListForm(existingList: list)
          .navigationTitle("Edit list")
      }
      .presentationDetents([.medium])
    }
  }
}

#Preview {
  NavigationStack {
    List {
      RemindersListRow(
        reminderCount: 10,
        remindersList: RemindersList(
          id: 1,
          name: "Personal"
        )
      )
    }
  }
}
