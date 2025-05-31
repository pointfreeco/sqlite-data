import SharingGRDB
import SwiftUI
import TipKit

@main
struct RemindersApp: App {
  @Dependency(\.context) var context

  init() {
    guard context == .live
    else { return }

    try! prepareDependencies {
      $0.defaultDatabase = try Reminders.appDatabase()
    }
    withErrorReporting {
      try Tips.configure()
    }
  }

  var body: some Scene {
    WindowGroup {
      if context == .live {
        NavigationStack {
          RemindersListsView()
        }
      }
    }
  }
}
