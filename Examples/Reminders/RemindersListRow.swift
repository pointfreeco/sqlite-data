import CloudKit
import SharingGRDB
import SwiftUI

struct RemindersListRow: View {
  let remindersCount: Int
  let remindersList: RemindersList
  let share: CKShare?

  @State var editList: RemindersList?

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
        if let shareMessage {
          Text(shareMessage)
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
        RemindersListForm(remindersList: RemindersList.Draft(list))
          .navigationTitle("Edit list")
      }
      .presentationDetents([.medium])
    }
  }

  var shareMessage: String? {
    guard let share
    else { return nil }
    if share.owner == share.currentUserParticipant {
      let participantNames = share.participants
        .filter { $0 != share.currentUserParticipant }
        .compactMap { $0.userIdentity.nameComponents?.formatted() }
        .joined(separator: ", ")
      if participantNames.count > 0 {
        return "Shared with \(participantNames)"
      } else {
        return "Shared"
      }
    } else if let ownerName = share.owner.userIdentity.nameComponents?.formatted() {
      return "Shared from \(ownerName)"
    } else {
      return nil
    }
  }
}

#Preview {
  NavigationStack {
    List {
      RemindersListRow(
        remindersCount: 10,
        remindersList: RemindersList(
          id: UUID(),
          title: "Personal"
        ),
        share: nil
      )
    }
  }
}
