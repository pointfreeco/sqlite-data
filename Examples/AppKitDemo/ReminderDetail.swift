import SQLiteData
import SwiftUI

@MainActor
@Observable
final class ReminderDetailModel {
  @ObservationIgnored @FetchOne var reminder: Reminder
  init(reminder: Reminder) {
    _reminder = FetchOne(
      wrappedValue: reminder,
      Reminder.find(reminder.id)
    )
  }
}

struct ReminderDetailView: View {
  let model: ReminderDetailModel
  var body: some View {
    Text(model.reminder.title)
  }
}

#Preview("Reminder") {
  let reminder = try! prepareDependencies {
    try $0.bootstrapDatabase()
    return try $0.defaultDatabase.read { db in
      try Reminder.all.fetchOne(db)!
    }
  }
  ReminderDetailView(
    model: ReminderDetailModel(
      reminder: reminder
    )
  )
}
