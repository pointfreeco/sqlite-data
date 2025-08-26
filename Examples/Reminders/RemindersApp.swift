import SharingGRDB
import SwiftUI

@main
struct RemindersApp: App {
  @Dependency(\.context) var context
  static let model = RemindersListsModel()

  init() {
    if context == .live {
      try! prepareDependencies {
        $0.defaultDatabase = try Reminders.appDatabase()
      }
    }
  }

  var body: some Scene {
    WindowGroup {
      if context == .live {
        NavigationStack {
          RemindersListsView(model: Self.model)
        }
      }
    }
  }
}
