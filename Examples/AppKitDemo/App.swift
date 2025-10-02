import CasePaths
import Observation

@Observable
final class AppModel {

  var destination: Destination?

  init(destination: Destination? = nil) {
    self.destination = destination
  }

  func reminderSelectedInOutline(_ reminder: Reminder) {
    self.destination = .reminder(ReminderDetailModel(reminder: reminder))
  }

  func remindersListSelectedInOutline(_ remindersList: RemindersList) {
    self.destination = .remindersList(RemindersListDetailModel(remindersList: remindersList))
  }

  @CasePathable
  enum Destination {
    case reminder(ReminderDetailModel)
    case remindersList(RemindersListDetailModel)
  }
}
