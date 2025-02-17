import Dependencies
import GRDB
import SwiftUI

@main
struct RemindersApp: App {
  init() {
    try! prepareDependencies {
      $0.defaultDatabase = try Reminders.appDatabase()
    }
  }
  
  var body: some Scene {
    WindowGroup {
      NavigationStack {
        RemindersListsView()
      }
    }
  }
}
