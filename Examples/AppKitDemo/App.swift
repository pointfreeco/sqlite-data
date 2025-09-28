import CasePaths
import Observation

@Observable
final class AppModel {

  var destination: Destination?

  init(destination: Destination? = nil) {
    self.destination = destination
  }

  @CasePathable
  enum Destination {
    case reminder(ReminderDetailModel)
    case remindersList(RemindersListDetailModel)
  }
}
