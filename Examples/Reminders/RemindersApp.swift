import CloudKit
import SharingGRDB
import SwiftUI

@main
struct RemindersApp: App {
  init() {
    try! prepareDependencies {
      $0.cloudKitDatabase = CloudKitDatabase(
        container: CKContainer(
          identifier: "iCloud.co.pointfree.sharing-grdb.Reminders"
        )
      )
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
