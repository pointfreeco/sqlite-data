import SharingGRDB
import SwiftUI

struct RemindersListRow: View {
  let reminderCount: Int
  let remindersList: RemindersList

  @State var editList: RemindersList?

  @Dependency(\.defaultDatabase) private var database

  var body: some View {
    HStack {
      Image(systemName: "list.bullet.circle.fill")
        .font(.largeTitle)
        .foregroundStyle(remindersList.color)
        .background(
          Color.white.clipShape(Circle()).padding(4)
        )
      Text(remindersList.title)
      Spacer()
      Text("\(reminderCount)")
        .foregroundStyle(.gray)
    }
    .swipeActions {
      Button {
        withErrorReporting {
          try database.write { db in
            try RemindersList.delete(remindersList)
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
        RemindersListForm(existingList: RemindersList.Draft(list))
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
          title: "Personal"
        )
      )
    }
  }
}
