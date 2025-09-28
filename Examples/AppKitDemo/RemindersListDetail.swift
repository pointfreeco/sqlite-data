import SQLiteData
import SwiftUI

@MainActor
@Observable
final class RemindersListDetailModel {
  @ObservationIgnored @FetchOne var remindersList: RemindersList
  @ObservationIgnored @FetchAll var reminders: [Reminder]
  var editableRemindersList: RemindersList.Draft?
  init(remindersList: RemindersList) {
    _remindersList = FetchOne(
      wrappedValue: remindersList,
      RemindersList.find(remindersList.id)
    )
    _reminders = FetchAll(
      Reminder.all
        .where { $0.remindersListID.eq(remindersList.id) }
        .order {
          ($0.isCompleted, $0.title)
        }
    )
  }
}

struct RemindersListDetailView: View {
  let model: RemindersListDetailModel
  var body: some View {
    List {
      ForEach(model.reminders) { reminder in
        Text(reminder.title)
      }
    }
    .safeAreaInset(edge: .top) {
      Text(model.remindersList.title)
        .font(.headline)
    }
  }
}

#Preview {
  let remindersList = try! prepareDependencies {
    try $0.bootstrapDatabase()
    return try $0.defaultDatabase.read { db in
      try RemindersList.all.fetchOne(db)!
    }
  }
  RemindersListDetailView(
    model: RemindersListDetailModel(
      remindersList: remindersList
    )
  )
}
