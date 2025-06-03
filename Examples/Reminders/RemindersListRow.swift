import CloudKit
import SharingGRDB
import SwiftUI

struct RemindersListRow: View {
  let remindersCount: Int
  let remindersList: RemindersList

  @State var editList: RemindersList?
  @State var participantNames: String?

  @Dependency(\.defaultDatabase) private var database
  @Dependency(\.defaultSyncEngine) private var syncEngine

  var body: some View {
    HStack {
      Image(systemName: "list.bullet.circle.fill")
        .font(.largeTitle)
        .foregroundStyle(remindersList.color)
        .background(
          Color.white.clipShape(Circle()).padding(4)
        )
      VStack(alignment: .leading, spacing: 4) {
        Text(remindersList.title)
        if let participantNames {
          Text("Shared with \(participantNames)")
            .font(.footnote)
            .foregroundStyle(Color.secondary)
        }
      }
      Spacer()
      Text("\(remindersCount)")
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
    .task {
      await withErrorReporting {
        guard let share = try await syncEngine.share(for: remindersList)
        else { return }
        participantNames = share.participants
          .filter { $0 != share.currentUserParticipant }
          .compactMap { $0.userIdentity.nameComponents?.formatted() }
          .joined(separator: ", ")
      }
    }
  }
}

#Preview {
  NavigationStack {
    List {
      RemindersListRow(
        remindersCount: 10,
        remindersList: RemindersList(
          id: UUID(1),
          title: "Personal"
        )
      )
    }
  }
}
