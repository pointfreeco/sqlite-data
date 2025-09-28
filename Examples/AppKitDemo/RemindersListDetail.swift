import SQLiteData
import SwiftUI

@MainActor
@Observable
final class RemindersListDetailModel {
  @ObservationIgnored @FetchOne var remindersList: RemindersList
  init(remindersList: RemindersList) {
    _remindersList = FetchOne(
      wrappedValue: remindersList,
      RemindersList.find(remindersList.id)
    )
  }
}

struct RemindersListDetailView: View {
  let model: RemindersListDetailModel
  var body: some View {
    Text("LIST")
    Text(model.remindersList.title)
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
