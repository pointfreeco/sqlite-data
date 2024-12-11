import Dependencies
import GRDB
import SwiftUI

@main
struct RemindersApp: App {
  init() {
    prepareDependencies {
      $0.defaultDatabase = .appDatabase
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
